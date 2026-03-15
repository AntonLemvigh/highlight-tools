import Foundation

/// Debounces rapid calls so the action only fires after a quiet period.
/// Used to prevent the popup from flickering during drag-to-select.
class Debouncer {

    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    /// Schedule an action. Any previously scheduled action is cancelled.
    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Cancel any pending action.
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
