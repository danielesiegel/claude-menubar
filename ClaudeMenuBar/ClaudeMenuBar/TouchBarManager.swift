import Foundation
import AppKit

@available(macOS 10.12.2, *)
class TouchBarManager: NSObject, NSTouchBarDelegate, NSTouchBarProvider {
    static let shared = TouchBarManager()

    private var _touchBar: NSTouchBar?
    private var currentAction: PendingAction?
    private var touchBarController: TouchBarWindowController?

    private let touchBarIdentifier = NSTouchBar.CustomizationIdentifier("com.claudemenubar.touchbar")
    private let approveIdentifier = NSTouchBarItem.Identifier("com.claudemenubar.approve")
    private let denyIdentifier = NSTouchBarItem.Identifier("com.claudemenubar.deny")
    private let labelIdentifier = NSTouchBarItem.Identifier("com.claudemenubar.label")

    var touchBar: NSTouchBar? {
        get {
            if _touchBar == nil {
                _touchBar = makeTouchBar()
            }
            return _touchBar
        }
        set {
            _touchBar = newValue
        }
    }

    override init() {
        super.init()
    }

    // MARK: - Show/Hide Touch Bar

    func showPermissionRequest(_ action: PendingAction) {
        guard UserDefaults.standard.bool(forKey: "enableTouchBar") != false else { return }

        currentAction = action

        DispatchQueue.main.async { [weak self] in
            self?.presentTouchBar()
        }
    }

    func hidePermissionRequest() {
        currentAction = nil
        dismissTouchBar()
    }

    private func presentTouchBar() {
        // Create a window controller to host the Touch Bar
        if touchBarController == nil {
            touchBarController = TouchBarWindowController()
        }

        touchBarController?.touchBarProvider = self
        _touchBar = nil // Force recreation
        touchBarController?.showWindow(nil)

        // Make the Touch Bar visible
        if let touchBar = touchBar {
            NSApp.touchBar = touchBar
        }
    }

    private func dismissTouchBar() {
        NSApp.touchBar = nil
        touchBarController?.close()
        _touchBar = nil
    }

    // MARK: - Touch Bar Creation

    private func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = touchBarIdentifier
        touchBar.defaultItemIdentifiers = [labelIdentifier, .flexibleSpace, denyIdentifier, approveIdentifier]
        touchBar.customizationAllowedItemIdentifiers = [labelIdentifier, denyIdentifier, approveIdentifier]
        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case labelIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = NSTextField(labelWithString: currentAction?.type.rawValue ?? "Approval Required")
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = NSColor.white
            item.view = label
            return item

        case approveIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                title: "✓ Approve",
                target: self,
                action: #selector(approveButtonTapped)
            )
            button.bezelColor = NSColor.systemGreen
            item.view = button
            return item

        case denyIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                title: "✗ Deny",
                target: self,
                action: #selector(denyButtonTapped)
            )
            button.bezelColor = NSColor.systemRed
            item.view = button
            return item

        default:
            return nil
        }
    }

    // MARK: - Actions

    @objc private func approveButtonTapped() {
        guard let action = currentAction else { return }
        ClaudeStateManager.shared.approveAction(action)
        hidePermissionRequest()
    }

    @objc private func denyButtonTapped() {
        guard let action = currentAction else { return }
        ClaudeStateManager.shared.denyAction(action)
        hidePermissionRequest()
    }
}

// MARK: - Touch Bar Window Controller

@available(macOS 10.12.2, *)
class TouchBarWindowController: NSWindowController {
    var touchBarProvider: NSTouchBarProvider?

    override var touchBar: NSTouchBar? {
        get { return touchBarProvider?.touchBar }
        set { }
    }

    init() {
        // Create an invisible window to host the Touch Bar
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Wrapper for version compatibility

class TouchBarManagerWrapper {
    static var shared: Any = {
        if #available(macOS 10.12.2, *) {
            return TouchBarManager.shared
        } else {
            return DummyTouchBarManager()
        }
    }()

    static func showPermissionRequest(_ action: PendingAction) {
        if #available(macOS 10.12.2, *) {
            TouchBarManager.shared.showPermissionRequest(action)
        }
    }

    static func hidePermissionRequest() {
        if #available(macOS 10.12.2, *) {
            TouchBarManager.shared.hidePermissionRequest()
        }
    }
}

class DummyTouchBarManager {
    func showPermissionRequest(_ action: PendingAction) {}
    func hidePermissionRequest() {}
}
