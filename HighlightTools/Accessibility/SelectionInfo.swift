import Foundation

/// Represents the currently selected text and its screen position.
/// Created by SelectionObserver when text is selected in any app.
struct SelectionInfo {
    /// The selected text content
    let text: String

    /// The bounding rectangle of the selection in screen coordinates (bottom-left origin).
    /// May be approximate if the app doesn't support kAXBoundsForRangeParameterizedAttribute.
    let bounds: CGRect

    /// The PID of the app where the selection was made
    let pid: pid_t
}
