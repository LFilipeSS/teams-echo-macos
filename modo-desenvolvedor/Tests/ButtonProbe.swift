import AppKit
import ApplicationServices

func value(_ el: AXUIElement, _ key: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, key as CFString, &v) == .success ? v : nil
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "br.com.luizfilipe.modo-desenvolvedor").first else { exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
guard let raw = value(ax, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID(),
      let button = (value(raw as! AXUIElement, "AXChildren") as? [AXUIElement])?.first else { exit(2) }
let title = value(button, "AXTitle") as? String ?? ""
let description = value(button, "AXDescription") as? String ?? ""
let label = value(button, "AXLabel") as? String ?? ""
print("STATUS BUTTON: title=\(title) description=\(description) label=\(label)")
guard [title, description, label].contains("desenvolvimento") else { exit(3) }
if CommandLine.arguments.contains("--click") {
    let result = AXUIElementPerformAction(button, "AXPress" as CFString)
    print("DIRECT BUTTON AXPress:", result.rawValue)
    if result != .success { exit(4) }
}
