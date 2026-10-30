import Cocoa

extension NSWindow {
    /// Shows the window in front of every other app's windows and makes it key.
    ///
    /// `NSApp.activate()` only asks to become the active app, and the system
    /// can say no. Without it `makeKeyAndOrderFront` puts the window in front
    /// of ReBezel's own windows only, so one that was already open stayed
    /// hidden behind the app the user was in.
    @MainActor
    func bringToFront() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}
