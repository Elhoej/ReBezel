import Cocoa

// There is no storyboard or nib, so NSApplicationMain would never instantiate
// the delegate. Set it up explicitly instead.
let app = NSApplication.shared
let delegate = AppDelegate()
// Under tests the app only hosts the test bundle: no event tap, no walkthrough.
if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
    app.delegate = delegate
}
app.run()
