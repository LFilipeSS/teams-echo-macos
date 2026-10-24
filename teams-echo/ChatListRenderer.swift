import CoreImage
import Foundation

struct ChatListRegion: Sendable {
    var left: Double = 13
    var top: Double = 50
    var width: Double = 367
    var rotateClockwise: Bool = true
    var splitColumns: Bool = false
}

final class ChatListRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var region: ChatListRegion
    let windowSize: CGSize

    init(windowSize: CGSize, region: ChatListRegion) { self.windowSize = windowSize; self.region = region }
    func update(_ region: ChatListRegion) { lock.lock(); defer { lock.unlock() }; self.region = region }

    func render(_ image: CIImage) -> CIImage? {
        lock.lock(); let region = self.region; lock.unlock()
        guard windowSize.width > 0, windowSize.height > 0, region.width >= 160,
              region.left >= 0, region.top >= 0 else { return nil }
        let sx = image.extent.width / windowSize.width
        let sy = image.extent.height / windowSize.height
        let left = image.extent.minX + region.left * sx
        let top = image.extent.maxY - region.top * sy
        let bounds = CGRect(x: left, y: image.extent.minY,
                            width: min(region.width * sx, image.extent.maxX - left),
                            height: top - image.extent.minY).integral.intersection(image.extent)
        guard bounds.width >= 100, bounds.height >= 100 else { return nil }
        var result = image.cropped(to: bounds).transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        if region.splitColumns {
            let partHeight = min(bounds.height, ceil(bounds.height / 2) + min(18 * sy, bounds.height / 8))
            let upper = CGRect(x: 0, y: bounds.height - partHeight, width: bounds.width, height: partHeight)
            let lower = CGRect(x: 0, y: 0, width: bounds.width, height: partHeight)
            let gap = 12 * sx
            let canvas = CGRect(x: 0, y: 0, width: bounds.width * 2 + gap, height: partHeight)
            let background = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.09)).cropped(to: canvas)
            let first = result.cropped(to: upper).transformed(by: CGAffineTransform(translationX: 0, y: -upper.minY))
            let second = result.cropped(to: lower).transformed(by: CGAffineTransform(translationX: bounds.width + gap, y: 0))
            result = first.composited(over: second.composited(over: background)).cropped(to: canvas)
        }
        if region.rotateClockwise { result = result.oriented(forExifOrientation: 6) }
        let scale = min(1280 / result.extent.width, 800 / result.extent.height)
        return result.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
