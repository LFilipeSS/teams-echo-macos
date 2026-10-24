import AppKit
import ScreenCaptureKit
import Network
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Foundation

struct EchoError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TeamsEcho/teams-echo.log")
func log(_ message: String) {
    try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
    if let file = try? FileHandle(forWritingTo: logURL) {
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8))
    }
}

func jpeg(_ image: CGImage) -> Data? {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
}

final class Frames: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var timestamp: Date?
    private var count = 0
    func update(_ jpeg: Data) { lock.lock(); defer { lock.unlock() }; data = jpeg; timestamp = Date(); count += 1 }
    func clear() { lock.lock(); defer { lock.unlock() }; data = nil; timestamp = nil; count = 0 }
    func snapshot() -> (Data?, Date?, Int) { lock.lock(); defer { lock.unlock() }; return (data, timestamp, count) }
}

struct Response {
    var status: Int
    var type: String
    var body: Data
    func encoded(headOnly: Bool = false) -> Data {
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 503: "Service Unavailable"][status] ?? "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store, max-age=0\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; img-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + (headOnly ? Data() : body)
    }
}

struct Router {
    let token: String
    let frames: Frames
    func response(method: String, path: String) -> Response {
        guard method == "GET" || method == "HEAD" else { return text(405, "Método não permitido") }
        let route = String(path.split(separator: "?", maxSplits: 1).first ?? "")
        if route == "/\(token)/" || route == "/\(token)" {
            return Response(status: 200, type: "text/html; charset=utf-8", body: Data(page.utf8))
        }
        if route == "/\(token)/frame.jpg" {
            let (data, date, _) = frames.snapshot()
            guard let data, date != nil else { return text(503, "Aguardando imagem do Teams") }
            return Response(status: 200, type: "image/jpeg", body: data)
        }
        if route == "/\(token)/status.json" {
            let (data, date, count) = frames.snapshot()
            let state: [String: Any] = ["ready": data != nil, "age": date.map { Date().timeIntervalSince($0) } ?? -1, "frames": count]
            return Response(status: 200, type: "application/json", body: (try? JSONSerialization.data(withJSONObject: state)) ?? Data())
        }
        return text(404, "Endereço não encontrado")
    }
    private func text(_ status: Int, _ value: String) -> Response { Response(status: status, type: "text/plain; charset=utf-8", body: Data(value.utf8)) }
    var page: String {
        """
        <!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><title>Teams na Echo</title>
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#111;color:white;font-family:Arial,sans-serif}#screen{display:block;width:100%;height:100%;object-fit:contain}#note{position:fixed;top:0;left:0;right:0;padding:12px;background:rgba(0,0,0,.8);text-align:center}#full{position:fixed;bottom:10px;right:10px;padding:10px;border:0;border-radius:6px;background:#333;color:white}</style></head>
        <body><img id="screen" alt="Lista de chats do Teams"><div id="note">Conectando à lista de chats…</div><button id="full">Tela cheia</button>
        <script>(function(){var image=document.getElementById('screen'),note=document.getElementById('note'),full=document.getElementById('full');
        function next(delay){setTimeout(function(){image.src='/\(token)/frame.jpg?t='+new Date().getTime();},delay);}
        image.onload=function(){note.style.display='none';next(200);};
        image.onerror=function(){note.innerHTML='Aguardando o Teams no Mac…';note.style.display='block';next(1000);};
        full.onclick=function(){var e=document.documentElement;if(e.requestFullscreen){e.requestFullscreen();}else if(e.webkitRequestFullscreen){e.webkitRequestFullscreen();}full.style.display='none';};
        document.body.ondblclick=function(){full.style.display='block';};next(0);})();</script></body></html>
        """
    }
}

final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if completed { return false }; completed = true; return true }
}

final class LocalServer: @unchecked Sendable {
    let queue = DispatchQueue(label: "TeamsEcho.HTTP", qos: .utility)
    let router: Router
    var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    init(router: Router) { self.router = router }
    func start(port: UInt16 = 3132) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            let id = ObjectIdentifier(connection)
            self.connections[id] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                if case .cancelled = state { self?.connections.removeValue(forKey: id) }
                if case .failed = state { connection?.cancel() }
            }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
            self.queue.asyncAfter(deadline: .now() + 8) { [weak connection] in connection?.cancel() }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = CompletionGate()
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    if let port = listener?.port, gate.claim() { continuation.resume(returning: port.rawValue) }
                case .failed(let error):
                    if gate.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if gate.claim() { continuation.resume(throwing: EchoError("Servidor encerrado")) }
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 10) { [weak listener] in
                if gate.claim() { listener?.cancel(); continuation.resume(throwing: EchoError("O servidor local não iniciou em 10 segundos")) }
            }
            listener.start(queue: queue)
        }
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            let request = accumulated + (data ?? Data())
            guard request.count <= 16384 else { connection.cancel(); return }
            if let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") {
                let parts = (text.components(separatedBy: "\r\n").first ?? "").split(separator: " ")
                let response: Response
                if parts.count == 3 { response = self.router.response(method: String(parts[0]), path: String(parts[1])) }
                else { response = Response(status: 400, type: "text/plain", body: Data()) }
                connection.send(content: response.encoded(headOnly: parts.first == "HEAD"), completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil { connection.cancel() }
            else { self.receive(connection, accumulated: request) }
        }
    }
    func stop() {
        listener?.cancel(); listener = nil
        queue.async { [weak self] in
            guard let self else { return }
            let active = Array(self.connections.values)
            self.connections.removeAll()
            for connection in active { connection.cancel() }
        }
    }
}

final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames: Frames
    let context = CIContext(options: [.cacheIntermediates: false])
    var stopped: ((Error) -> Void)?
    let renderer: ChatListRenderer
    private let renderLock = NSLock()
    private var lastSource: CIImage?
    private var active = true
    init(frames: Frames, renderer: ChatListRenderer) { self.frames = frames; self.renderer = renderer }
    private func publish(_ source: CIImage) {
        guard let image = renderer.render(source),
              let cgImage = context.createCGImage(image, from: image.extent), let data = jpeg(cgImage) else { frames.clear(); return }
        frames.update(data)
    }
    func updateRegion(_ region: ChatListRegion) {
        renderLock.lock(); defer { renderLock.unlock() }
        renderer.update(region)
        if active, let source = lastSource { publish(source) }
    }
    func stopRendering() {
        renderLock.lock(); defer { renderLock.unlock() }
        active = false; lastSource = nil; frames.clear()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer), let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        renderLock.lock(); defer { renderLock.unlock() }
        guard active else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        lastSource = source; publish(source)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { stopRendering(); stopped?(error) }
}

@MainActor
final class TeamsCapture {
    let frames: Frames
    var stream: SCStream?
    var output: CaptureOutput?
    var region = ChatListRegion(
        left: UserDefaults.standard.object(forKey: "ChatListLeft") as? Double ?? 13,
        top: UserDefaults.standard.object(forKey: "ChatListTop") as? Double ?? 50,
        width: UserDefaults.standard.object(forKey: "ChatListWidth") as? Double ?? 367,
        rotateClockwise: UserDefaults.standard.object(forKey: "ChatListRotateClockwise") as? Bool ?? true,
        splitColumns: UserDefaults.standard.object(forKey: "ChatListTwoColumnsEnabled") as? Bool ?? false)
    func updateRegion(_ region: ChatListRegion) {
        self.region = region; output?.updateRegion(region)
        UserDefaults.standard.set(region.left, forKey: "ChatListLeft")
        UserDefaults.standard.set(region.top, forKey: "ChatListTop")
        UserDefaults.standard.set(region.width, forKey: "ChatListWidth")
        UserDefaults.standard.set(region.rotateClockwise, forKey: "ChatListRotateClockwise")
        UserDefaults.standard.set(region.splitColumns, forKey: "ChatListTwoColumnsEnabled")
    }
    init(frames: Frames) { self.frames = frames }
    func start() async throws {
        guard CGPreflightScreenCaptureAccess() else { throw EchoError("Autorize Teams Echo em Privacidade e Segurança → Gravação de Tela e Áudio do Sistema e reabra o aplicativo.") }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.teams2").isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.teams2") {
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        var selected: SCWindow?
        for _ in 0..<30 {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            selected = content.windows.filter {
                ["com.microsoft.teams2", "com.microsoft.teams"].contains($0.owningApplication?.bundleIdentifier ?? "") &&
                $0.windowLayer == 0 && $0.frame.width > 250 && $0.frame.height > 180
            }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            if selected != nil { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        guard let window = selected else { throw EchoError("Abra uma janela do Microsoft Teams e clique em Iniciar novamente.") }
        let config = SCStreamConfiguration()
        // Capture at window resolution, then crop BEFORE reducing or JPEG encoding.
        config.width = max(2, Int(window.frame.width) / 2 * 2)
        config.height = max(2, Int(window.frame.height) / 2 * 2)
        if #available(macOS 14.2, *) { config.ignoreShadowsSingleWindow = true }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
        let output = CaptureOutput(frames: frames, renderer: ChatListRenderer(windowSize: window.frame.size, region: region))
        output.stopped = { error in log("CAPTURA encerrada: \(error.localizedDescription)") }
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "TeamsEcho.JPEG", qos: .userInitiated))
        self.output = output; self.stream = stream
        try await stream.startCapture()
        for _ in 0..<60 {
            if frames.snapshot().0 != nil { log("CAPTURA iniciada: lista de chats; origem=\(config.width)x\(config.height); recorte x=\(region.left), topo=\(region.top), largura=\(region.width); rotação 90°=\(region.rotateClockwise); duas colunas=\(region.splitColumns); sem áudio"); return }
            try await Task.sleep(for: .milliseconds(100))
        }
        await stop()
        throw EchoError("O Teams ainda não forneceu uma imagem. Deixe a janela aberta e sem minimizar.")
    }
    func stop() async { output?.stopRendering(); try? await stream?.stopCapture(); stream = nil; output = nil; frames.clear() }
}

func localAddress() -> String? {
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0 else { return nil }
    defer { freeifaddrs(interfaces) }
    var choices: [(String, String)] = []
    var current = interfaces
    while let pointer = current {
        defer { current = pointer.pointee.ifa_next }
        guard let address = pointer.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: pointer.pointee.ifa_name)
        guard name.hasPrefix("en"), pointer.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            choices.append((name, String(cString: host)))
        }
    }
    return choices.sorted { ($0.0 == "en0" ? 0 : 1, $0.0) < ($1.0 == "en0" ? 0 : 1, $1.0) }.first?.1
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let frames = Frames()
    var capture: TeamsCapture!
    var server: LocalServer?
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var status: NSTextField!
    var address: NSTextField!
    var busy = false
    var widthField: NSTextField!
    var leftField: NSTextField!
    var topField: NSTextField!
    var rotateButton: NSButton!
    var splitButton: NSButton!
    var link = ""
    var token: String {
        if let saved = UserDefaults.standard.string(forKey: "ViewerToken"), saved.count == 16, saved.allSatisfy(\.isHexDigit) { return saved }
        let token = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
        UserDefaults.standard.set(token, forKey: "ViewerToken")
        return token
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        capture = TeamsCapture(frames: frames)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Teams → Echo"
        let menu = NSMenu()
        for (title, action) in [("Abrir painel", #selector(show)), ("Iniciar transmissão", #selector(start)), ("Parar transmissão", #selector(stop)), ("Sair", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        statusItem.menu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 480), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Teams na Echo — gratuito"; window.isReleasedWhenClosed = false; window.center()
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: "Teams na Echo"); heading.font = .systemFont(ofSize: 23, weight: .semibold)
        stack.addArrangedSubview(heading)
        let description = NSTextField(wrappingLabelWithString: "Acompanhe os indicadores de mensagens não lidas. Escolha uma ou duas colunas e, se usar a Echo de lado, ative a rotação de 90°.")
        stack.addArrangedSubview(description)
        status = NSTextField(wrappingLabelWithString: "Preparando…"); stack.addArrangedSubview(status)
        address = NSTextField(labelWithString: ""); address.isSelectable = true; address.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        address.lineBreakMode = .byCharWrapping; address.maximumNumberOfLines = 3; stack.addArrangedSubview(address)
        let buttons = NSStackView(); buttons.spacing = 12
        for (title, action) in [("Iniciar", #selector(start)), ("Copiar endereço", #selector(copyAddress)), ("Parar", #selector(stop)), ("Autorizar captura", #selector(authorize))] {
            buttons.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        stack.addArrangedSubview(buttons)
        let cropControls = NSStackView(); cropControls.spacing = 8
        for (title, value) in [("Esquerda", capture.region.left), ("Topo", capture.region.top), ("Largura", capture.region.width)] {
            cropControls.addArrangedSubview(NSTextField(labelWithString: title))
            let field = NSTextField(string: String(Int(value))); field.widthAnchor.constraint(equalToConstant: 55).isActive = true
            cropControls.addArrangedSubview(field)
            if title == "Esquerda" { leftField = field }; if title == "Topo" { topField = field }; if title == "Largura" { widthField = field }
        }
        cropControls.addArrangedSubview(NSButton(title: "Aplicar recorte", target: self, action: #selector(applyRegion)))
        stack.addArrangedSubview(cropControls)
        rotateButton = NSButton(checkboxWithTitle: "Girar imagem 90° para a direita", target: self, action: #selector(applyRegion))
        rotateButton.state = capture.region.rotateClockwise ? .on : .off; stack.addArrangedSubview(rotateButton)
        splitButton = NSButton(checkboxWithTitle: "Exibir em duas colunas", target: self, action: #selector(applyRegion))
        splitButton.state = capture.region.splitColumns ? .on : .off; stack.addArrangedSubview(splitButton)
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "Mantenha a janela do Teams aberta e sem minimizar. Controle o Teams e o áudio pelo Mac."))
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)])
        show(); start()
    }
    @objc func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(); start(); return true
    }
    @objc func start() {
        guard !busy else { return }
        if server != nil { show(); return }
        guard CGPreflightScreenCaptureAccess() else {
            status.stringValue = "Autorize Teams Echo em Gravação de Tela e Áudio do Sistema. Depois encerre e reabra este aplicativo."
            authorize(); return
        }
        busy = true; status.stringValue = "Localizando a janela do Teams…"
        Task { @MainActor in
            defer { busy = false }
            do {
                try await capture.start()
                guard let ip = localAddress() else { throw EchoError("Conecte o Mac ao Wi-Fi ou Ethernet para obter o endereço local.") }
                let server = LocalServer(router: Router(token: token, frames: frames))
                self.server = server
                let port = try await server.start()
                link = "http://\(ip):\(port)/\(token)/"
                address.stringValue = link
                status.stringValue = "Transmitindo somente o recorte da lista de chats. Os indicadores de não lidas são os mesmos exibidos pelo Teams."
                log("SERVIDOR local iniciado na porta \(port)")
            } catch {
                server?.stop(); server = nil; await capture.stop()
                status.stringValue = error.localizedDescription; address.stringValue = ""; link = ""
                log("ERRO: \(error.localizedDescription)")
            }
        }
    }
    @objc func stop() {
        guard !busy else { return }
        busy = true
        server?.stop(); server = nil; frames.clear()
        status.stringValue = "Transmissão parada."; address.stringValue = ""; link = ""
        Task { @MainActor in await capture.stop(); busy = false }
        log("PARADA pelo usuário")
    }
    @objc func copyAddress() { guard !link.isEmpty else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string) }
    @objc func applyRegion() {
        guard let left = Double(leftField.stringValue), let top = Double(topField.stringValue), let width = Double(widthField.stringValue),
              left.isFinite, top.isFinite, width.isFinite, (0...1500).contains(left), (0...1000).contains(top), (160...1000).contains(width) else {
            status.stringValue = "Use números válidos: esquerda e topo positivos; largura entre 160 e 1000."; return
        }
        capture.updateRegion(ChatListRegion(left: left, top: top, width: width, rotateClockwise: rotateButton.state == .on, splitColumns: splitButton.state == .on))
        status.stringValue = "Recorte da lista atualizado. Ajustes salvos para as próximas ativações."
    }
    @objc func authorize() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc func quit() { server?.stop(); frames.clear(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { server?.stop(); frames.clear() }
}

@main struct TeamsEcho {
    @MainActor static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--capture-test") {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do {
                    if CommandLine.arguments.contains("--capture-test") { try await SelfTests.capture() }
                    else { try await SelfTests.run() }
                    exit(0)
                }
                catch { print("FAIL: \(error)"); exit(1) }
            }
            app.run(); return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "br.com.luizfilipe.teams-echo").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { return }
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
