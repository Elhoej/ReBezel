import Cocoa

/// First-run walkthrough: choose a bezel style, choose a position, then grant
/// Accessibility access. The owner previews the bezel as choices change and
/// closes the window once the permission has been detected.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    enum Step: Int, CaseIterable {
        case style
        case position
        case permission
    }

    /// Called whenever a bezel setting changed or a step that shows one appeared.
    var onPreviewRequested: (() -> Void)?
    /// Called when the user asks to grant Accessibility access.
    var onPermissionRequested: (() -> Void)?
    /// Called when the user finishes the last step while access is already granted.
    var onFinished: (() -> Void)?
    /// Called when the window closes, for any reason.
    var onClose: (() -> Void)?

    private var step: Step = .style { didSet { render() } }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let stepContainer = NSView()
    private let progressLabel = NSTextField(labelWithString: "")
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let primaryButton = NSButton(title: "Continue", target: nil, action: nil)

    private lazy var styleButtons = makeRadioButtons(
        titles: HUDStyle.allCases.map(\.title),
        action: #selector(styleChanged(_:))
    )
    private lazy var positionButtons = makeRadioButtons(
        titles: HUDPosition.allCases.map(\.title),
        action: #selector(positionChanged(_:))
    )
    private lazy var styleView = makeChoiceView(buttons: styleButtons)
    private lazy var positionView = makeChoiceView(buttons: positionButtons)
    private lazy var permissionView = makePermissionView()
    private let permissionSpinner = NSProgressIndicator()
    private let permissionStatus = NSTextField(labelWithString: "")

    private let contentWidth: CGFloat = 400

    init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ReBezel"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let content = makeContentView()
        window.contentView = content
        render()
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        step = .style
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The owner saw the permission arrive; nothing left to do here.
    func finish() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        iconView.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 44, weight: .light))
        iconView.contentTintColor = .controlAccentColor
        iconView.imageScaling = .scaleNone

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.alignment = .center

        bodyLabel.alignment = .center
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = contentWidth

        progressLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        progressLabel.textColor = .tertiaryLabelColor

        backButton.target = self
        backButton.action = #selector(goBack)
        primaryButton.target = self
        primaryButton.action = #selector(primaryAction)
        primaryButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [progressLabel, NSView(), backButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.setHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [iconView, titleLabel, bodyLabel, stepContainer, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(6, after: titleLabel)
        stack.setCustomSpacing(20, after: bodyLabel)
        stack.setCustomSpacing(24, after: stepContainer)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)

        stepContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth + 48),
            stepContainer.widthAnchor.constraint(equalToConstant: contentWidth),
            buttons.widthAnchor.constraint(equalToConstant: contentWidth),
            bodyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: contentWidth),
        ])
        return stack
    }

    /// Radio buttons sharing one action form a group automatically.
    private func makeRadioButtons(titles: [String], action: Selector) -> [NSButton] {
        titles.enumerated().map { index, title in
            let button = NSButton(radioButtonWithTitle: title, target: self, action: action)
            button.tag = index
            return button
        }
    }

    /// A vertical group of radio buttons, centred in the step area.
    private func makeChoiceView(buttons: [NSButton]) -> NSView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return centered(stack)
    }

    private func makePermissionView() -> NSView {
        permissionSpinner.style = .spinning
        permissionSpinner.controlSize = .small
        permissionSpinner.isDisplayedWhenStopped = false

        permissionStatus.textColor = .secondaryLabelColor

        let status = NSStackView(views: [permissionSpinner, permissionStatus])
        status.orientation = .horizontal
        status.spacing = 6
        return centered(status)
    }

    private func centered(_ view: NSView) -> NSView {
        let container = NSView()
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        return container
    }

    private func setStepView(_ view: NSView) {
        stepContainer.subviews.forEach { $0.removeFromSuperview() }
        stepContainer.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: stepContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: stepContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: stepContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: stepContainer.trailingAnchor),
        ])
    }

    // MARK: - Steps

    private func render() {
        progressLabel.stringValue = "Step \(step.rawValue + 1) of \(Step.allCases.count)"
        backButton.isHidden = step == .style
        permissionSpinner.stopAnimation(nil)

        switch step {
        case .style:
            titleLabel.stringValue = "Choose a style"
            bodyLabel.stringValue = "This is the bezel you will see when changing the volume or brightness. Pick the look you like; each choice is previewed on screen."
            styleButtons.forEach { $0.state = $0.tag == HUDStyle.allCases.firstIndex(of: Preferences.hudStyle) ? .on : .off }
            setStepView(styleView)
            primaryButton.title = "Continue"
            onPreviewRequested?()

        case .position:
            titleLabel.stringValue = "Choose a position"
            bodyLabel.stringValue = "Where on the screen should the bezel appear?"
            positionButtons.forEach { $0.state = $0.tag == HUDPosition.allCases.firstIndex(of: Preferences.hudPosition) ? .on : .off }
            setStepView(positionView)
            primaryButton.title = "Continue"
            onPreviewRequested?()

        case .permission:
            titleLabel.stringValue = "Allow Accessibility access"
            bodyLabel.stringValue = "ReBezel needs Accessibility access to catch the volume and brightness keys before macOS shows its own banner. Open System Settings and turn on ReBezel in the Accessibility list. This window closes on its own once that is done."
            setStepView(permissionView)
            if AXIsProcessTrusted() {
                permissionStatus.stringValue = "Accessibility access is already granted."
                primaryButton.title = "Finish"
            } else {
                permissionStatus.stringValue = "Waiting for Accessibility access…"
                permissionSpinner.startAnimation(nil)
                primaryButton.title = "Open System Settings…"
            }
        }

        window?.contentView?.layoutSubtreeIfNeeded()
        if let window, let content = window.contentView {
            window.setContentSize(content.fittingSize)
        }
    }

    // MARK: - Actions

    @objc private func styleChanged(_ sender: NSButton) {
        Preferences.hudStyle = HUDStyle.allCases[sender.tag]
        onPreviewRequested?()
    }

    @objc private func positionChanged(_ sender: NSButton) {
        Preferences.hudPosition = HUDPosition.allCases[sender.tag]
        onPreviewRequested?()
    }

    @objc private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    @objc private func primaryAction() {
        switch step {
        case .style:
            step = .position
        case .position:
            step = .permission
        case .permission:
            if AXIsProcessTrusted() {
                onFinished?()
                finish()
            } else {
                onPermissionRequested?()
            }
        }
    }
}
