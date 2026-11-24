import Foundation
import CoreGraphics

/// UI motion derived from zoomFromTo 0x42bb40 and doubles at 0x73f4e0.
/// The same curve is used for the requested Mac rectangle transitions; native per-node morphing is not claimed.
public enum TreemapMotion {
    public static let duration: TimeInterval = 0.5 // native default zoomTimeMs = 5 * 100
    public static func progress(_ fraction: Double) -> Double {
        if fraction <= 0 { return 0 }
        if fraction >= 1 { return 1 }
        let q = (cos(fraction * 3.1415) + 1) * 0.5
        return 1 - q * q
    }
    public static func interpolate(from: CGRect, to: CGRect, progress: Double) -> CGRect {
        let p = min(1, max(0, progress))
        return CGRect(x: from.minX + (to.minX - from.minX) * p,
                      y: from.minY + (to.minY - from.minY) * p,
                      width: from.width + (to.width - from.width) * p,
                      height: from.height + (to.height - from.height) * p)
    }
}
