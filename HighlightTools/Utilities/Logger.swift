import Foundation
import os

/// App-wide logger using Apple's unified logging system.
/// Usage: AppLogger.accessibility.info("Selection changed")
enum AppLogger {
    static let accessibility = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HighlightTools", category: "Accessibility")
    static let popup = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HighlightTools", category: "Popup")
    static let llm = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HighlightTools", category: "LLM")
    static let general = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HighlightTools", category: "General")
}
