import AppKit
import Foundation
import ImageIO

enum SelfTests {
    @MainActor static func capture() async throws {
        let frames = Frames()
        let capture = TeamsCapture(frames: frames)
        try await capture.start()
        guard let data = frames.snapshot().0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw EchoError("Captura não produziu JPEG válido") }
        try require(image.width <= 1280 && image.height <= 800, "Dimensões inesperadas")
        if let index = CommandLine.arguments.firstIndex(of: "--preview-output"), CommandLine.arguments.count > index + 1 {
            let file = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        let server = LocalServer(router: Router(token: "local-capture-test", frames: frames))
        let port = try await server.start(port: 0)
        defer { server.stop() }
        let (received, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/local-capture-test/frame.jpg")!)
        try require((response as? HTTPURLResponse)?.statusCode == 200, "Transmissão HTTP da captura falhou")
        try require(CGImageSourceCreateWithData(received as CFData, nil) != nil, "Resposta não contém JPEG")
        let original = capture.region
        let previousCount = frames.snapshot().2
        var changed = original; changed.splitColumns.toggle()
        capture.updateRegion(changed)
        try require(frames.snapshot().2 > previousCount, "Checkbox não atualizou o quadro imediatamente")
        capture.updateRegion(original)
        await capture.stop()
        try require(frames.snapshot().0 == nil, "Captura não foi limpa")
        print("PASS: recorte da lista de chats capturado e transmitido por HTTP local; JPEG \(image.width)x\(image.height)")
    }

    static func require(_ value: Bool, _ message: String) throws { if !value { throw EchoError(message) } }
    static func run() async throws {
        try crop()
        let frames = Frames()
        let router = Router(token: "test-only-token", frames: frames)
        try require(router.response(method: "GET", path: "/wrong/frame.jpg").status == 404, "Link sem token deve ser recusado")
        try require(router.response(method: "GET", path: "/test-only-token/frame.jpg").status == 503, "Não servir imagem inexistente")
        try require(router.response(method: "POST", path: "/test-only-token/").status == 405, "Não aceitar comandos remotos")
        let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let image = jpeg(context.makeImage()!)!
        try require(CGImageSourceGetCount(CGImageSourceCreateWithData(image as CFData, nil)!) == 1, "JPEG inválido")
        frames.update(image)
        let server = LocalServer(router: router)
        let port = try await server.start(port: 0)
        defer { server.stop(); frames.clear() }
        let base = "http://127.0.0.1:\(port)/test-only-token"
        let (page, pageResponse) = try await URLSession.shared.data(from: URL(string: base + "/")!)
        try require((pageResponse as? HTTPURLResponse)?.statusCode == 200, "HTTP do visualizador")
        try require(String(decoding: page, as: UTF8.self).contains("frame.jpg"), "Visualizador não usa quadros locais")
        async let one = URLSession.shared.data(from: URL(string: base + "/frame.jpg?t=1")!)
        async let two = URLSession.shared.data(from: URL(string: base + "/frame.jpg?t=2")!)
        async let three = URLSession.shared.data(from: URL(string: base + "/frame.jpg?t=3")!)
        for (bytes, response) in try await [one, two, three] {
            try require(bytes == image && (response as? HTTPURLResponse)?.statusCode == 200, "Clientes simultâneos não recebem o mesmo JPEG")
        }
        let (_, forbidden) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        try require((forbidden as? HTTPURLResponse)?.statusCode == 404, "Não expor captura fora do link privado")
        frames.clear()
        let (_, stopped) = try await URLSession.shared.data(from: URL(string: base + "/frame.jpg")!)
        try require((stopped as? HTTPURLResponse)?.statusCode == 503, "Não manter captura após parar")
        print("PASS: HTTP real, link privado, JPEG válido, três clientes simultâneos e limpeza ao parar. Nenhuma captura de tela usada neste teste.")
    }

    static func crop() throws {
        let bounds = CGRect(x: 0, y: 0, width: 512, height: 800)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)
        let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 10, y: 400, width: 180, height: 400))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 10, y: 0, width: 180, height: 400))
        let source = green.composited(over: blue.composited(over: red))
        let renderer = ChatListRenderer(windowSize: bounds.size, region: ChatListRegion(left: 10, top: 0, width: 180))
        guard let result = renderer.render(source) else { throw EchoError("Recorte sintético indisponível") }
        let context = CIContext()
        func color(_ result: CIImage, _ x: CGFloat, _ y: CGFloat) -> [UInt8] {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(result, toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: result.extent.width * x, y: result.extent.height * y, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return pixel
        }
        _ = result
        for split in [false, true] {
            for rotated in [false, true] {
                renderer.update(ChatListRegion(left: 10, top: 0, width: 180, rotateClockwise: rotated, splitColumns: split))
                guard let image = renderer.render(source) else { throw EchoError("Combinação indisponível") }
                let green: [UInt8], blue: [UInt8]
                if split && !rotated { green = color(image, 0.25, 0.5); blue = color(image, 0.75, 0.5) }
                else if !split && rotated { green = color(image, 0.75, 0.5); blue = color(image, 0.25, 0.5) }
                else { green = color(image, 0.5, 0.75); blue = color(image, 0.5, 0.25) }
                try require(green[0] < 10 && green[1] > 240 && blue[0] < 10 && blue[2] > 240,
                            "Ordem da lista incorreta ou conversa incluída: colunas=\(split), rotação=\(rotated)")
                try require(image.extent.width <= 1280.01 && image.extent.height <= 800.01, "Recorte fora do limite")
            }
        }
        print("PASS: quatro combinações independentes de colunas e rotação; ordem preservada e conversa excluída")
    }
}
