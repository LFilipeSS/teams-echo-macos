import Foundation
import CoreGraphics

@main struct GeometryTests {
    static func main() {
        // Primary screen with menu and bottom Dock.
        assert(LayoutGeometry.accessibilityFrame(visible: CGRect(x: 0, y: 70, width: 5120, height: 1345), primaryHeight: 1440) == CGRect(x: 0, y: 25, width: 5120, height: 1345))
        // Secondary screens above and to the left must retain negative AX coordinates.
        assert(LayoutGeometry.accessibilityFrame(visible: CGRect(x: -5120, y: 1440, width: 5120, height: 1415), primaryHeight: 1440) == CGRect(x: -5120, y: -1415, width: 5120, height: 1415))
        for width in [1920.0, 2560, 5120, 3441] {
            let bounds = CGRect(x: -500, y: -300, width: width, height: 1300)
            let columns = LayoutGeometry.columns(in: bounds)
            assert(columns[0].minX == bounds.minX && columns[2].maxX == bounds.maxX)
            assert(columns[0].maxX == columns[1].minX && columns[1].maxX == columns[2].minX)
            assert(columns.allSatisfy { $0.minY == bounds.minY && $0.height == bounds.height })
            assert(abs(columns[0].width / width - 0.5) < 0.001)
            assert(abs(columns[1].width / width - 0.25) < 0.001)
        }
        assert(!LayoutGeometry.matches(CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 4, y: 0, width: 100, height: 100)))
        print("PASS: coordenadas multimonitor, barra/Dock, arredondamento e proporções")
    }
}
