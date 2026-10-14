import Cocoa

/// A single-pane Preferences window holding every user-facing option.
/// The window is built in code (the app has no storyboard) and reads its
/// initial state from `Preferences` / `LaunchAtLogin` each time it is shown.
@MainActor
final class PreferencesWindowController: NSWindowController {
    /// Called after a setting that affects the bezel changes, so the owner can preview it.
    var onHUDSettingChanged: (() -> Void)?
    /// Called once the user has confirmed hiding the menu bar icon.
    var onHideMenuBarIcon: (() -> Void)?

    private let positionPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let stylePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let allScreensCheckbox = NSButton(checkboxWithTitle: "Show on all screens", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let hideIconButton = NSButton(title: "Hide Menu Bar Icon…", target: nil, action: nil)
    private let hideIconNote = NSTextField(wrappingLabelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ReBezel Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let content = makeContentView()
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Brings the window to the front, refreshing every control first.
    func show() {
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        for position in HUDPosition.allCases {
            positionPopUp.addItem(withTitle: position.title)
            positionPopUp.lastItem?.representedObject = position.rawValue
        }
        positionPopUp.target = self
        positionPopUp.action = #selector(positionChanged)

        for style in HUDStyle.allCases {
            stylePopUp.addItem(withTitle: style.title)
            stylePopUp.lastItem?.representedObject = style.rawValue
        }
        stylePopUp.target = self
        stylePopUp.action = #selector(styleChanged)

        allScreensCheckbox.target = self
        allScreensCheckbox.action = #selector(allScreensChanged)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

        hideIconButton.target = self
        hideIconButton.action = #selector(hideMenuBarIcon)

        hideIconNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hideIconNote.textColor = .secondaryLabelColor
        hideIconNote.preferredMaxLayoutWidth = 260

        let grid = NSGridView(views: [
            [label("Position:"), positionPopUp],
            [label("Style:"), stylePopUp],
            [NSGridCell.emptyContentView, allScreensCheckbox],
            [label("Startup:"), launchAtLoginCheckbox],
            [label("Menu bar:"), hideIconButton],
            [NSGridCell.emptyContentView, hideIconNote],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        // A little extra air between the bezel settings and the app settings.
        grid.row(at: 3).topPadding = 8
        grid.row(at: 5).topPadding = -4

        let container = NSView()
        container.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        return container
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    /// Syncs every control with the current persisted state.
    private func refresh() {
        positionPopUp.selectItem(at: HUDPosition.allCases.firstIndex(of: Preferences.hudPosition) ?? 0)
        stylePopUp.selectItem(at: HUDStyle.allCases.firstIndex(of: Preferences.hudStyle) ?? 0)
        allScreensCheckbox.state = Preferences.showOnAllScreens ? .on : .off
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off

        let hidden = Preferences.hideMenuBarIcon
        hideIconButton.isEnabled = !hidden
        hideIconNote.stringValue = hidden
            ? "The icon is hidden. Open ReBezel again from Finder, Spotlight or Launchpad to show it."
            : "ReBezel keeps running without the icon. Open ReBezel again to bring it back."
    }

    // MARK: - Actions

    @objc private func positionChanged() {
        guard let raw = positionPopUp.selectedItem?.representedObject as? String,
              let position = HUDPosition(rawValue: raw) else { return }
        Preferences.hudPosition = position
        onHUDSettingChanged?()
    }

    @objc private func styleChanged() {
        guard let raw = stylePopUp.selectedItem?.representedObject as? String,
              let style = HUDStyle(rawValue: raw) else { return }
        Preferences.hudStyle = style
        onHUDSettingChanged?()
    }

    @objc private func allScreensChanged() {
        Preferences.showOnAllScreens = allScreensCheckbox.state == .on
        onHUDSettingChanged?()
    }

    @objc private func launchAtLoginChanged() {
        LaunchAtLogin.setEnabled(launchAtLoginCheckbox.state == .on)
        // Registration can fail; reflect what actually happened.
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func hideMenuBarIcon() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = "ReBezel keeps running in the background. To show the icon again (or to quit), open ReBezel from Finder, Spotlight or Launchpad while it is running."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.onHideMenuBarIcon?()
            self?.refresh()
        }
    }
}
