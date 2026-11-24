import SwiftUI
import AppKit

/// Records the first native draw of the overview, rather than treating an
/// engine callback as a displayed frame. No published state is mutated here.
struct OverviewPaintProbe: NSViewRepresentable {
    let onPaint: @MainActor () -> Void
    final class PaintView: NSView {
        var onPaint: (@MainActor () -> Void)?
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if window?.isVisible == true, !isHiddenOrHasHiddenAncestor { onPaint?() }
        }
    }
    func makeNSView(context: Context) -> PaintView { PaintView() }
    func updateNSView(_ view: PaintView, context: Context) {
        view.onPaint = onPaint; view.needsDisplay = true
    }
}
