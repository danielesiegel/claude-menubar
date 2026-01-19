import SwiftUI
import AppKit

@main
struct ClaudeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var stateManager = ClaudeStateManager.shared
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar only app
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupEventMonitor()

        // Request notification permissions
        NotificationManager.shared.requestPermission()

        // Start monitoring for Claude instances
        stateManager.startMonitoring()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusIcon(active: false)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Observe Claude state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(claudeStateChanged),
            name: .claudeStateDidChange,
            object: nil
        )
    }

    func updateStatusIcon(active: Bool) {
        guard let button = statusItem?.button else { return }

        if active {
            // Claude logo when active - using SF Symbol as fallback
            if let image = NSImage(named: "ClaudeIcon") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else {
                // Fallback to SF Symbol
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude")?
                    .withSymbolConfiguration(config)
            }
            button.appearsDisabled = false
        } else {
            // Dimmed when no Claude instance
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude")?
                .withSymbolConfiguration(config)
            button.appearsDisabled = true
        }
    }

    func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.delegate = self
        popover?.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(stateManager)
                .environmentObject(NotificationManager.shared)
        )
    }

    func setupEventMonitor() {
        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func claudeStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusIcon(active: self?.stateManager.isClaudeActive ?? false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        stateManager.stopMonitoring()
    }
}

extension Notification.Name {
    static let claudeStateDidChange = Notification.Name("claudeStateDidChange")
    static let claudePermissionRequest = Notification.Name("claudePermissionRequest")
    static let claudeTaskComplete = Notification.Name("claudeTaskComplete")
}
