import Cocoa

// There is no storyboard or nib, so NSApplicationMain would never instantiate
// the delegate. Set it up explicitly instead.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
