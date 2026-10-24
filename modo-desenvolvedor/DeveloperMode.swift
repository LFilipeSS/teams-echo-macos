import AppKit
import ApplicationServices
import ServiceManagement

let appID = "br.com.luizfilipe.modo-desenvolvedor"
let targets = [("Google Chrome", "com.google.Chrome"), ("ChatGPT/Codex", "com.openai.codex"), ("Visual Studio Code", "com.microsoft.VSCode")]
let logDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ModoDesenvolvedor", isDirectory: true)

func log(_ message: String) {
    try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    let url = logDirectory.appendingPathComponent("modo-desenvolvedor.log")
    if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, size > 2_000_000 {
        let old = logDirectory.appendingPathComponent("modo-desenvolvedor.previous.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
    let data = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data)
    }
}

struct ModeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool {
    (attribute(element, name) as? NSNumber)?.boolValue ?? false
}
func frameOf(_ window: AXUIElement) -> CGRect? {
    guard let p = attribute(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = attribute(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
          point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
          size.width > 100, size.height > 100 else { return nil }
    return CGRect(origin: point, size: size)
}
func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) throws {
    let result = AXUIElementSetAttributeValue(element, name as CFString, value)
    guard result == .success else { throw ModeError("AX \(name): erro \(result.rawValue)") }
}
func settable(_ window: AXUIElement, _ name: String) -> Bool {
    var result: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(window, name as CFString, &result) == .success && result.boolValue
}
func selectWindow(_ pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    // Electron exposes its complete accessibility tree when a client requests it.
    _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    let all = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    let preferred = [elementAttribute(app, kAXMainWindowAttribute), elementAttribute(app, kAXFocusedWindowAttribute)].compactMap { $0 }
    let candidates = preferred + all
    return candidates.first { window in
        let movable = settable(window, kAXPositionAttribute) && settable(window, kAXSizeAttribute)
        let restorable = (boolAttribute(window, "AXFullScreen") && settable(window, "AXFullScreen")) ||
            (boolAttribute(window, kAXMinimizedAttribute) && settable(window, kAXMinimizedAttribute))
        return (attribute(window, kAXRoleAttribute) as? String) == kAXWindowRole &&
        (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole &&
        frameOf(window) != nil && (movable || restorable)
    }
}
func frameJSON(_ rect: CGRect) -> [String: Double] {
    ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
}
func jsonData(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
}
func printJSON(_ object: Any) { print(String(decoding: jsonData(object), as: UTF8.self)) }

@MainActor
final class LayoutEngine {
    func ensureDockHidden() async throws {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw ModeError("Dock: processo não localizado; nenhum aplicativo foi aberto")
        }
        log("DOCK: preparando ocultação antes de abrir qualquer aplicativo")
        let ax = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        let lists = attribute(ax, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let dockItems = lists.flatMap { attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
        guard let separator = dockItems.first(where: { (attribute($0, kAXSubroleAttribute) as? String) == "AXSeparatorDockItem" }) else {
            throw ModeError("Dock: separador de configurações não localizado")
        }
        let shown = AXUIElementPerformAction(separator, "AXShowMenu" as CFString)
        guard shown == .success else { throw ModeError("Dock: não foi possível acessar a ocultação (AX=\(shown.rawValue))") }
        var menu: AXUIElement?
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            menu = (attribute(separator, kAXChildrenAttribute) as? [AXUIElement] ?? [])
                .first { (attribute($0, kAXRoleAttribute) as? String) == kAXMenuRole }
            if menu != nil { break }
        }
        guard let menu else { throw ModeError("Dock: menu de configurações indisponível") }
        defer { _ = AXUIElementPerformAction(menu, "AXCancel" as CFString) }
        let commands = attribute(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let enableTitles = ["Ativar Ocultação", "Turn Hiding On"]
        let disableTitles = ["Desativar Ocultação", "Turn Hiding Off"]
        if let enable = commands.first(where: { command in
            guard let title = attribute(command, kAXTitleAttribute) as? String else { return false }
            return enableTitles.contains { $0.caseInsensitiveCompare(title) == .orderedSame }
        }) {
            let pressed = AXUIElementPerformAction(enable, kAXPressAction as CFString)
            guard pressed == .success else { throw ModeError("Dock: falha ao ativar a ocultação (AX=\(pressed.rawValue))") }
            log("DOCK: ocultação automática ativada pelo comando nativo")
        } else if commands.contains(where: { command in
            guard let title = attribute(command, kAXTitleAttribute) as? String else { return false }
            return disableTitles.contains { $0.caseInsensitiveCompare(title) == .orderedSame }
        }) {
            _ = AXUIElementPerformAction(menu, "AXCancel" as CFString)
            log("DOCK: ocultação automática já habilitada")
        } else {
            throw ModeError("Dock: comando de ocultação não reconhecido no idioma atual")
        }
        var previousFrame: CGRect?
        var stableSamples = 0
        let domain = "com.apple.dock" as CFString
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(200))
            _ = CFPreferencesAppSynchronize(domain)
            let hidden = (CFPreferencesCopyAppValue("autohide" as CFString, domain) as? NSNumber)?.boolValue == true
            let (screen, _) = try screenAndFrames()
            let frame = screen.frame
            let visible = screen.visibleFrame
            let noDockBand = abs(visible.minX - frame.minX) <= 3 &&
                abs(visible.maxX - frame.maxX) <= 3 && abs(visible.minY - frame.minY) <= 3
            if hidden && noDockBand && previousFrame == visible { stableSamples += 1 }
            else { stableSamples = 0 }
            previousFrame = visible
            if stableSamples >= 2 {
                log("DOCK: ocultação confirmada; área útil estabilizada=\(visible); aplicativos podem ser abertos")
                return
            }
        }
        throw ModeError("Dock: a ocultação não foi confirmada; nenhum aplicativo foi aberto")
    }

    func screenAndFrames() throws -> (NSScreen, [CGRect]) {
        guard let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.max(by: {
                  if $0.frame.width != $1.frame.width { return $0.frame.width < $1.frame.width }
                  return $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
              }) else { throw ModeError("Nenhuma tela disponível") }
        let frame = LayoutGeometry.accessibilityFrame(visible: screen.visibleFrame, primaryHeight: primary.frame.maxY)
        return (screen, LayoutGeometry.columns(in: frame))
    }

    func inspect(verify: Bool) throws -> [String: Any] {
        guard AXIsProcessTrusted() else { throw ModeError("Permissão de Acessibilidade necessária") }
        let (screen, frames) = try screenAndFrames()
        var rows: [[String: Any]] = []
        for (index, target) in targets.enumerated() {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: target.1)
            let window = apps.first.flatMap { selectWindow($0.processIdentifier) }
            var row: [String: Any] = ["app": target.0, "bundleID": target.1, "running": !apps.isEmpty, "expected": frameJSON(frames[index])]
            if let window, let rect = frameOf(window) {
                row["actual"] = frameJSON(rect)
                row["widthFraction"] = rect.width / screen.visibleFrame.width
                row["minimized"] = boolAttribute(window, kAXMinimizedAttribute)
                row["fullScreen"] = boolAttribute(window, "AXFullScreen")
                row["matches"] = LayoutGeometry.matches(rect, frames[index]) && !boolAttribute(window, kAXMinimizedAttribute) && !boolAttribute(window, "AXFullScreen")
            } else { row["matches"] = false }
            if !verify, let app = apps.first {
                let ax = AXUIElementCreateApplication(app.processIdentifier)
                row["windows"] = (attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? []).map { w -> [String: Any] in
                    ["role": attribute(w, kAXRoleAttribute) as? String ?? "?", "subrole": attribute(w, kAXSubroleAttribute) as? String ?? "?", "frame": frameOf(w).map(frameJSON) ?? [:], "sizeSettable": settable(w, kAXSizeAttribute)]
                }
            }
            rows.append(row)
        }
        return ["timestamp": ISO8601DateFormatter().string(from: Date()), "screen": screen.localizedName,
                "visibleFrameAppKit": frameJSON(screen.visibleFrame), "windows": rows,
                "passed": rows.allSatisfy { ($0["matches"] as? Bool) == true }]
    }

    func open(_ bundleID: String) async throws -> NSRunningApplication {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ModeError("Aplicativo não localizado: \(bundleID)")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: ModeError("Abertura sem processo: \(bundleID)")) }
            }
        }
    }

    func readyWindow(_ target: (String, String)) async throws -> AXUIElement {
        var app: NSRunningApplication
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.1).first {
            app = running; log("LOCALIZAÇÃO \(target.0): processo existente pid=\(app.processIdentifier)")
            if selectWindow(app.processIdentifier) == nil { app = try await open(target.1) }
        } else {
            log("ABERTURA \(target.0): aplicativo fechado; iniciando \(target.1)")
            app = try await open(target.1)
            log("ABERTURA \(target.0): pid=\(app.processIdentifier)")
        }
        for _ in 0..<180 {
            if app.isTerminated { throw ModeError("\(target.0) encerrou durante a abertura") }
            if let window = selectWindow(app.processIdentifier) {
                app.activate()
                if boolAttribute(window, "AXFullScreen") {
                    log("RESTAURAR \(target.0): saindo da tela cheia")
                    try setAttribute(window, "AXFullScreen", kCFBooleanFalse)
                    for _ in 0..<80 {
                        if !boolAttribute(window, "AXFullScreen") { break }
                        try await Task.sleep(for: .milliseconds(150))
                    }
                    guard !boolAttribute(window, "AXFullScreen") else { throw ModeError("\(target.0): tela cheia não foi encerrada") }
                    try await Task.sleep(for: .milliseconds(1200))
                }
                // Reacquire after a Space/fullscreen transition (Electron may replace AX objects).
                let current = selectWindow(app.processIdentifier) ?? window
                if boolAttribute(current, kAXMinimizedAttribute) {
                    log("RESTAURAR \(target.0): janela minimizada")
                    try setAttribute(current, kAXMinimizedAttribute, kCFBooleanFalse)
                    try await Task.sleep(for: .milliseconds(400))
                }
                _ = AXUIElementPerformAction(current, kAXRaiseAction as CFString)
                return current
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw ModeError("\(target.0): nenhuma janela padrão redimensionável em 45 segundos; painéis e diálogos são ignorados")
    }

    func place(_ window: AXUIElement, frame: CGRect, name: String) async throws {
        for attempt in 1...8 {
            var point = frame.origin; var size = frame.size
            guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { throw ModeError("AXValue inválido") }
            // Move first to transfer the window to the target display, then resize and move again.
            try setAttribute(window, kAXPositionAttribute, p)
            try setAttribute(window, kAXSizeAttribute, s)
            try setAttribute(window, kAXPositionAttribute, p)
            try await Task.sleep(for: .milliseconds(300))
            if let actual = frameOf(window), LayoutGeometry.matches(actual, frame) {
                log("POSIÇÃO \(name): tentativa=\(attempt) x=\(actual.minX) y=\(actual.minY) largura=\(actual.width) altura=\(actual.height)")
                return
            }
        }
        throw ModeError("\(name): tamanho/posição recusados; esperado=\(frame), obtido=\(String(describing: frameOf(window)))")
    }

    func run() async throws -> [String: Any] {
        guard AXIsProcessTrusted() else { throw ModeError("Permissão de Acessibilidade necessária") }
        try await ensureDockHidden()
        let (screen, frames) = try screenAndFrames()
        log("INÍCIO tela=\(screen.localizedName) frame=\(screen.frame) útil=\(screen.visibleFrame)")
        for (index, target) in targets.enumerated() {
            do {
                let window = try await readyWindow(target)
                try await place(window, frame: frames[index], name: target.0)
            } catch { log("ERRO \(target.0): \(error.localizedDescription)"); throw error }
        }
        try await Task.sleep(for: .milliseconds(700))
        let report = try inspect(verify: true)
        guard report["passed"] as? Bool == true else { throw ModeError("Verificação final das três janelas falhou: \(String(decoding: jsonData(report), as: UTF8.self))") }
        log("SUCESSO: três janelas verificadas via AX; proporções 50% / 25% / 25%")
        return report
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var activateItem: NSMenuItem!
    var statusLine: NSMenuItem!
    var secondaryMenu: NSMenu!
    var working = false
    let engine = LayoutEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        item.button?.title = "desenvolvimento"
        item.button?.toolTip = "Ativar Modo Desenvolvedor · clique direito para Sair"
        item.button?.setAccessibilityLabel("desenvolvimento")
        item.button?.setAccessibilityIdentifier(appID + ".status")
        item.button?.target = self
        item.button?.action = #selector(statusButtonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        activateItem = NSMenuItem(title: "Ativar Modo Desenvolvedor", action: #selector(activateMode), keyEquivalent: "")
        activateItem.target = self; menu.addItem(activateItem)
        statusLine = NSMenuItem(title: AXIsProcessTrusted() ? "Pronto" : "Acessibilidade necessária", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false; menu.addItem(statusLine)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        secondaryMenu = menu
        log("APP INICIADO bundle=\(Bundle.main.bundleIdentifier ?? "?") caminho=\(Bundle.main.bundlePath) AX=\(AXIsProcessTrusted())")
        if !UserDefaults.standard.bool(forKey: "LoginRegistered") {
            do {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                if SMAppService.mainApp.status == .enabled { UserDefaults.standard.set(true, forKey: "LoginRegistered") }
                log("INÍCIO AUTOMÁTICO status=\(SMAppService.mainApp.status.rawValue)")
            } catch { log("ERRO INÍCIO AUTOMÁTICO: \(error.localizedDescription)") }
        }
    }

    @objc func statusButtonClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            NSMenu.popUpContextMenu(secondaryMenu, with: event, for: sender)
        } else {
            log("BOTÃO: desenvolvimento")
            activateMode()
        }
    }

    func updateStatus(_ message: String) {
        statusLine.title = message
        item.button?.toolTip = message + " · clique para ativar; clique direito para Sair"
    }

    @objc func activateMode() {
        guard !working else { return }
        log("ATIVAÇÃO: Modo Desenvolvedor")
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            updateStatus("Autorize em Ajustes → Acessibilidade")
            log("PERMISSÃO: aguardando autorização de Acessibilidade do aplicativo final assinado")
            return
        }
        working = true; activateItem.isEnabled = false; updateStatus("Organizando janelas…")
        Task { @MainActor in
            defer { working = false; activateItem.isEnabled = true }
            do {
                var report = try await engine.run()
                try jsonData(report).write(to: logDirectory.appendingPathComponent("ultima-execucao.json"), options: .atomic)
                updateStatus("Layout verificado: 50% · 25% · 25%")
                if EchoIntegration.isConfigured {
                    updateStatus("Layout verificado · abrindo Teams na Echo…")
                    do {
                        report["echo"] = try await EchoIntegration().run()
                        updateStatus("Layout verificado · comando enviado à Echo Show")
                    } catch {
                        log("FALHA ECHO: \(error.localizedDescription)")
                        report["echo"] = ["requested": true, "commandAccepted": false, "error": error.localizedDescription]
                        updateStatus("Layout verificado · falha na conexão com a Echo")
                        let alert = NSAlert(); alert.messageText = "O layout foi aplicado, mas a Echo precisa de atenção"
                        alert.informativeText = error.localizedDescription
                        alert.addButton(withTitle: "OK"); alert.runModal()
                    }
                    try? jsonData(report).write(to: logDirectory.appendingPathComponent("ultima-execucao.json"), options: .atomic)
                }
            } catch {
                log("FALHA: \(error.localizedDescription)")
                try? jsonData(["passed": false, "error": error.localizedDescription]).write(to: logDirectory.appendingPathComponent("ultima-execucao.json"), options: .atomic)
                updateStatus("Falha — consulte o log")
                let alert = NSAlert(); alert.messageText = "Não foi possível concluir o layout"
                alert.informativeText = error.localizedDescription + "\n\nLog: " + logDirectory.path
                alert.addButton(withTitle: "OK"); alert.runModal()
            }
        }
    }
    @objc func quitApp() { log("APP ENCERRADO pelo menu"); NSApp.terminate(nil) }
}

#if !LAYOUT_TEST
@main
struct DeveloperMode {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--refresh-login") {
            do {
                if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
                try SMAppService.mainApp.register()
                guard SMAppService.mainApp.status == .enabled else { throw ModeError("Início automático requer autorização nos Ajustes") }
                UserDefaults.standard.set(true, forKey: "LoginRegistered")
                log("INÍCIO AUTOMÁTICO: registro renovado para a versão final; status=\(SMAppService.mainApp.status.rawValue)")
                print("Login habilitado para " + Bundle.main.bundlePath)
            } catch { print(error.localizedDescription); exit(1) }
            return
        }
        if arguments.contains("--diagnose") {
            let engine = LayoutEngine()
            let layout = try? engine.screenAndFrames()
            printJSON(["trusted": AXIsProcessTrusted(), "bundle": Bundle.main.bundleIdentifier ?? "?", "loginStatus": SMAppService.mainApp.status.rawValue,
                       "screens": NSScreen.screens.map { ["name": $0.localizedName, "frame": frameJSON($0.frame), "visible": frameJSON($0.visibleFrame)] },
                       "expected": layout?.1.map(frameJSON) ?? []])
            return
        }
        if arguments.contains("--verify") || arguments.contains("--inspect") {
            do {
                let report = try LayoutEngine().inspect(verify: arguments.contains("--verify"))
                printJSON(report)
                exit(report["passed"] as? Bool == true ? 0 : 2)
            } catch { printJSON(["passed": false, "error": error.localizedDescription]); exit(1) }
        }
        if arguments.contains("--prepare-minimized") || arguments.contains("--prepare-fullscreen") {
            do {
                guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: targets[0].1).first,
                      let w = selectWindow(app.processIdentifier) else { throw ModeError("Chrome/janela/AX indisponível") }
                try setAttribute(w, arguments.contains("--prepare-minimized") ? kAXMinimizedAttribute : "AXFullScreen", kCFBooleanTrue)
                print("Preparação solicitada via AX")
            } catch { print(error.localizedDescription); exit(1) }
            return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: appID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
