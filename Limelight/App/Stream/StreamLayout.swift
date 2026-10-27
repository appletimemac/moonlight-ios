import CoreGraphics
import Foundation

// Where the stream screen puts the video and the iPhone Duo panel. Portrait-shaped
// areas only happen on the iPhone Duo inner display (it ignores the landscape lock),
// flat or half folded like a laptop; they split at the crease with the game on top.
@objc(StreamLayout)
final class StreamLayout: NSObject {
    @objc let videoFrame: CGRect
    @objc let panelFrame: CGRect

    @objc var isSplit: Bool {
        !panelFrame.isEmpty
    }

    init(videoFrame: CGRect, panelFrame: CGRect) {
        self.videoFrame = videoFrame
        self.panelFrame = panelFrame
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? StreamLayout else { return false }
        return videoFrame == other.videoFrame && panelFrame == other.panelFrame
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(videoFrame.origin.x)
        hasher.combine(videoFrame.origin.y)
        hasher.combine(videoFrame.size.width)
        hasher.combine(videoFrame.size.height)
        hasher.combine(panelFrame.origin.y)
        return hasher.finalize()
    }

    // crease is the division reserved region in the same coordinate space as bounds,
    // or .null. Flat, the region is inactive with no height, which still marks the
    // physical crease.
    @objc(layoutWithBounds:crease:)
    static func layout(bounds: CGRect, crease: CGRect) -> StreamLayout {
        guard bounds.height > bounds.width else {
            return StreamLayout(videoFrame: bounds, panelFrame: .zero)
        }

        var videoBottom = bounds.midY.rounded(.down)
        var panelTop = videoBottom
        // Only a crease that leaves both sides a real share of the view counts
        let margin = bounds.height / 4
        if !crease.isNull,
           crease.width >= bounds.width / 2,
           crease.height < bounds.height / 3,
           crease.minY >= bounds.minY + margin,
           crease.maxY <= bounds.maxY - margin {
            videoBottom = crease.minY
            panelTop = crease.maxY
        }

        return StreamLayout(
            videoFrame: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: videoBottom - bounds.minY),
            panelFrame: CGRect(x: bounds.minX, y: panelTop, width: bounds.width, height: bounds.maxY - panelTop))
    }
}
