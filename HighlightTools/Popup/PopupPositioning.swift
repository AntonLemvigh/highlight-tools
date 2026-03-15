import Cocoa

/// Calculates where to position the popup relative to the text selection.
enum PopupPositioning {

    private static let verticalOffset: CGFloat = 3  // Minimal gap — practically touching the selection

    /// Calculate the popup origin given the selection bounds and popup size.
    /// The popup sits just above the top edge of the selection, centered horizontally.
    /// Falls below if there's no room above.
    static func position(popupSize: CGSize, selectionBounds: CGRect) -> CGPoint {
        let selectionMidX = selectionBounds.midX
        let screen = ScreenGeometry.screen(containing: CGPoint(x: selectionMidX, y: selectionBounds.midY))

        // Desired position: centered, just above the top of the selection
        let x = selectionMidX - popupSize.width / 2
        // In AppKit (bottom-left origin), "above" means higher Y = selection.maxY + offset
        var y = selectionBounds.maxY + verticalOffset

        // If popup would go above the visible screen, place it below the selection instead
        if y + popupSize.height > screen.visibleFrame.maxY {
            y = selectionBounds.minY - verticalOffset - popupSize.height
        }

        let unclamped = CGRect(x: x, y: y, width: popupSize.width, height: popupSize.height)
        let clamped = ScreenGeometry.clamp(frame: unclamped, to: screen)

        return clamped.origin
    }
}
