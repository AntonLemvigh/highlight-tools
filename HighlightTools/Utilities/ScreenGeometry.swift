import Cocoa

/// Helper utilities for working with screen coordinates and multi-monitor setups.
enum ScreenGeometry {

    /// Returns the NSScreen that contains the given point, or the main screen as fallback.
    static func screen(containing point: CGPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// Clamps a window frame within the visible area of the given screen.
    /// Accounts for menu bar and Dock.
    static func clamp(frame: CGRect, to screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        var result = frame

        // Clamp horizontally
        if result.maxX > visible.maxX {
            result.origin.x = visible.maxX - result.width
        }
        if result.minX < visible.minX {
            result.origin.x = visible.minX
        }

        // Clamp vertically
        if result.minY < visible.minY {
            result.origin.y = visible.minY
        }
        if result.maxY > visible.maxY {
            result.origin.y = visible.maxY - result.height
        }

        return result
    }
}
