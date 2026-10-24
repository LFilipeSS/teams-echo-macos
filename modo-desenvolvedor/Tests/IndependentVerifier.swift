import AppKit
import ApplicationServices
import ServiceManagement

func read(_ el: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, key as CFString, &result) == .success ? result : nil
}
func rect(_ el: AXUIElement) -> CGRect? {
    guard let p = read(el, "AXPosition"), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = read(el, "AXSize"), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
func fields(_ r: CGRect) -> [String: CGFloat] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }

guard let screen = NSScreen.screens.max(by: { $0.frame.width < $1.frame.width }), let primary = NSScreen.screens.first else { fatalError("No screen") }
let usable = screen.visibleFrame
let dockHidden = (CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? NSNumber)?.boolValue ?? false
let expectedY = primary.frame.maxY - usable.maxY
let ids = ["com.google.Chrome", "com.openai.codex", "com.microsoft.VSCode"]
let starts = [0.0, 0.5, 0.75]; let fractions = [0.5, 0.25, 0.25]
var results: [[String: Any]] = []
var passed = true
for (index, id) in ids.enumerated() {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { fatalError("App absent: " + id) }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    let windows = read(ax, "AXWindows") as? [AXUIElement] ?? []
    let valid = windows.filter { w in
        guard read(w, "AXSubrole") as? String == "AXStandardWindow", let r = rect(w) else { return false }
        return abs(r.minX - (usable.minX + usable.width * starts[index])) <= 3 &&
            abs(r.minY - expectedY) <= 3 && abs(r.width - usable.width * fractions[index]) <= 3 && abs(r.height - usable.height) <= 3 &&
            !(read(w, "AXMinimized") as? Bool ?? false) && !(read(w, "AXFullScreen") as? Bool ?? false)
    }
    let ok = !valid.isEmpty; passed = passed && ok
    var row: [String: Any] = ["bundleID": id, "passed": ok, "pid": app.processIdentifier]
    if let frame = valid.first.flatMap(rect) { row["actual"] = fields(frame); row["fraction"] = frame.width / usable.width }
    results.append(row)
}
guard let mode = NSRunningApplication.runningApplications(withBundleIdentifier: "br.com.luizfilipe.modo-desenvolvedor").first else { fatalError("Menu app absent") }
let modeAX = AXUIElementCreateApplication(mode.processIdentifier)
var barVisible = false
var buttonFrame: [String: CGFloat] = [:]
if let raw = read(modeAX, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() {
    let bar = raw as! AXUIElement
    if let button = (read(bar, "AXChildren") as? [AXUIElement])?.first, let frame = rect(button) {
        barVisible = screen.frame.intersects(CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height))
        buttonFrame = fields(frame)
    }
}
let noDock = mode.activationPolicy == .accessory
passed = passed && barVisible && noDock
let output: [String: Any] = ["passed": passed, "timestamp": ISO8601DateFormatter().string(from: Date()), "screen": screen.localizedName,
    "usableAppKit": fields(usable), "dockAutoHidden": dockHidden, "windows": results, "statusItemOnScreen": barVisible, "statusItemAXFrame": buttonFrame, "absentFromDock": noDock]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
exit(passed ? 0 : 1)
