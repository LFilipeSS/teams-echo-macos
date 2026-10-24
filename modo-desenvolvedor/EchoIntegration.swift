import AppKit
import ApplicationServices

@MainActor
struct EchoIntegration {
    private let bundleID = "br.com.luizfilipe.teams-echo"

    static var isConfigured: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TeamsEcho/Alexa/integration.json")
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return config["enabled"] as? Bool == true
    }

    private func viewerToken() -> String? {
        UserDefaults.standard.persistentDomain(forName: bundleID)?["ViewerToken"] as? String
    }

    private func streamReady() async -> Bool {
        guard let token = viewerToken(), token.count == 16, token.allSatisfy(\.isHexDigit),
              let url = URL(string: "http://127.0.0.1:3132/\(token)/status.json") else { return false }
        var request = URLRequest(url: url); request.timeoutInterval = 1
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let state = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return state["ready"] as? Bool == true && (state["frames"] as? Int ?? 0) > 0
        } catch { return false }
    }

    private func findStartButton(_ parent: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 8 else { return nil }
        if (attribute(parent, kAXRoleAttribute) as? String) == kAXButtonRole,
           (attribute(parent, kAXTitleAttribute) as? String) == "Iniciar", boolAttribute(parent, kAXEnabledAttribute) {
            return parent
        }
        for child in attribute(parent, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let found = findStartButton(child, depth: depth + 1) { return found }
        }
        return nil
    }

    private func prepareStream() async throws {
        if await streamReady() { log("ECHO: transmissão do Teams já disponível"); return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ModeError("Teams Echo não foi localizado em Aplicativos.")
        }
        let previous = NSWorkspace.shared.frontmostApplication
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        defer { app.hide(); previous?.activate() }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        var pressed = false
        for _ in 0..<40 {
            if await streamReady() { log("ECHO: transmissão do Teams iniciada e confirmada"); return }
            if !pressed, let button = findStartButton(ax) {
                let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
                guard result == .success else { throw ModeError("Teams Echo: o botão Iniciar recusou a ação (AX=\(result.rawValue)).") }
                pressed = true
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ModeError("Teams Echo não iniciou a transmissão. Abra seu painel e confira a permissão de Gravação de Tela.")
    }

    func run(workerOverride: URL? = nil) async throws -> [String: Any] {
        try await prepareStream()
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TeamsEcho/Alexa")
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("integration.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let node = config["node"] as? String, FileManager.default.isExecutableFile(atPath: node),
              let worker = workerOverride ?? Bundle.main.resourceURL?.appendingPathComponent("AlexaBridge/open-teams.cjs"),
              FileManager.default.fileExists(atPath: worker.path) else {
            throw ModeError("Conexão com a Alexa não configurada neste Mac.")
        }
        log("ECHO: transmissão pronta; solicitando abertura da skill na Echo Show 8")
        let process = Process(); process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [worker.path]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { task in continuation.resume(returning: task.terminationStatus) }
            do { try process.run() }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        let result = try? JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: Any]
        guard exitCode == 0, result?["state"] as? String == "ALEXA_OPEN_REQUEST_SENT" else {
            let state = result?["state"] as? String ?? "ALEXA_WORKER_FAILED"
            log("ERRO ECHO: \(state)")
            if state == "VIEWER_ADDRESS_CHANGED" {
                throw ModeError("O endereço do Mac mudou. Atualize o endereço do Teams Echo na configuração da skill.")
            }
            throw ModeError("A Alexa não confirmou o envio do comando (\(state)). O layout das janelas foi preservado.")
        }
        log("ECHO: comando aceito pela Amazon para a Echo Show 8; isso não confirma a renderização física")
        return ["requested": true, "commandAccepted": true, "device": "Echo Show 8"]
    }
}
