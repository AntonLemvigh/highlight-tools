import Cocoa

// Explicit app setup — more reliable than @main for menubar-only apps.
// Creates the NSApplication, sets our delegate, and starts the run loop.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
