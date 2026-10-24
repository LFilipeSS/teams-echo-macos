import Foundation
import CoreGraphics

enum LayoutGeometry {
    // AppKit: bottom-left of primary display. AX: top-left of primary display.
    static func accessibilityFrame(visible: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: visible.minX, y: primaryHeight - visible.maxY,
               width: visible.width, height: visible.height)
    }

    static func columns(in frame: CGRect) -> [CGRect] {
        let middle = frame.minX + (frame.width * 0.5).rounded()
        let last = frame.minX + (frame.width * 0.75).rounded()
        return [CGRect(x: frame.minX, y: frame.minY, width: middle - frame.minX, height: frame.height),
                CGRect(x: middle, y: frame.minY, width: last - middle, height: frame.height),
                CGRect(x: last, y: frame.minY, width: frame.maxX - last, height: frame.height)]
    }

    static func matches(_ actual: CGRect, _ expected: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(actual.minX - expected.minX) <= tolerance && abs(actual.minY - expected.minY) <= tolerance &&
        abs(actual.width - expected.width) <= tolerance && abs(actual.height - expected.height) <= tolerance
    }
}
