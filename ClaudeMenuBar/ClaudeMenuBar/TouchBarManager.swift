import Foundation
import AppKit

@available(macOS 10.12.2, *)
class TouchBarManager: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarManager()

    private var touchBar: NSTouchBar?
    private var currentAction: PendingAction?
    private var touchBarWindow: NSWindow?

    private let touchBarIdentifier = NSTouchBar.CustomizationIdentifier("com.claudemenubar.touchbar")
    private let approveIdentifier = NSTouchBarItem.Identifier("com.claudemenubar.approve")
    private let denyIdentifier = NSTouchBarItem.Identifier("com.claudemenubar.deny")
    private let labelIdentifier = NSTouchBarItem.Identifier("com.claudemenubar.label")
    private let statusIdentifier = NSTouchBarItem.Identifier("com.claudemenubar.status")

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
        // Create a minimal window to host the Touch Bar
        if touchBarWindow == nil {
            touchBarWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            touchBarWindow?.isReleasedWhenClosed = false
            touchBarWindow?.level = .floating
            touchBarWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary]
        }

        touchBar = makeTouchBar()

        // Present the Touch Bar
        if #available(macOS 10.14, *) {
            NSTouchBar.presentSystemModalTouchBar(touchBar!, systemTrayItemIdentifier: statusIdentifier)
        }
    }

    private func dismissTouchBar() {
        if #available(macOS 10.14, *) {
            NSTouchBar.dismissSystemModalTouchBar(touchBar!)
        }
        touchBar = nil
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

        case statusIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let imageView = NSImageView()
            if let image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude") {
                imageView.image = image
            }
            item.view = imageView
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

// MARK: - Fallback for older macOS

class TouchBarManagerFallback {
    static let shared: Any = {
        if #available(macOS 10.12.2, *) {
            return TouchBarManager.shared
        } else {
            return TouchBarManagerFallback()
        }
    }()

    func showPermissionRequest(_ action: PendingAction) {
        // No-op on older macOS
    }

    func hidePermissionRequest() {
        // No-op on older macOS
    }
}
