import Foundation
import UserNotifications
import AppKit

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var permissionGranted = false

    private let notificationCenter = UNUserNotificationCenter.current()

    override init() {
        super.init()
        notificationCenter.delegate = self
        checkPermissionStatus()
        setupNotificationCategories()
        setupObservers()
    }

    // MARK: - Permission

    func requestPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
            }
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func checkPermissionStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.permissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Categories with Actions

    private func setupNotificationCategories() {
        // Approve/Deny action category
        let approveAction = UNNotificationAction(
            identifier: "APPROVE_ACTION",
            title: "Approve",
            options: [.foreground]
        )

        let denyAction = UNNotificationAction(
            identifier: "DENY_ACTION",
            title: "Deny",
            options: [.destructive]
        )

        let permissionCategory = UNNotificationCategory(
            identifier: "PERMISSION_REQUEST",
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Task complete category
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: [.foreground]
        )

        let taskCompleteCategory = UNNotificationCategory(
            identifier: "TASK_COMPLETE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([permissionCategory, taskCompleteCategory])
    }

    // MARK: - Observers

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePermissionRequest(_:)),
            name: .claudePermissionRequest,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTaskComplete(_:)),
            name: .claudeTaskComplete,
            object: nil
        )
    }

    // MARK: - Send Notifications

    @objc private func handlePermissionRequest(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "enablePermissionNotifications") != false,
              let action = notification.object as? PendingAction else {
            return
        }

        sendPermissionNotification(for: action)

        // Also show popover from menu bar
        showPermissionPopover(for: action)

        // Update Touch Bar
        TouchBarManagerWrapper.showPermissionRequest(action)
    }

    @objc private func handleTaskComplete(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "showTaskCompletePopover") != false else {
            return
        }

        sendTaskCompleteNotification()
        showTaskCompletePopover()
    }

    func sendPermissionNotification(for action: PendingAction) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code - Approval Required"
        content.subtitle = action.type
        content.body = action.description
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"
        content.userInfo = ["actionId": action.id]

        let request = UNNotificationRequest(
            identifier: "permission-\(action.id)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }

    func sendTaskCompleteNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body = "Task completed successfully"
        content.sound = .default
        content.categoryIdentifier = "TASK_COMPLETE"

        let request = UNNotificationRequest(
            identifier: "task-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }

    // MARK: - Popovers

    private func showPermissionPopover(for action: PendingAction) {
        // Find the app delegate and show popover
        if let appDelegate = NSApp.delegate as? AppDelegate {
            DispatchQueue.main.async {
                appDelegate.togglePopover()
            }
        }
    }

    private func showTaskCompletePopover() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            DispatchQueue.main.async {
                appDelegate.togglePopover()
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        if let actionIdString = userInfo["actionId"] as? String,
           let action = ClaudeStateManager.shared.pendingActions.first(where: { $0.id == actionIdString }) {

            switch actionIdentifier {
            case "APPROVE_ACTION":
                ClaudeStateManager.shared.approveAction(action)
            case "DENY_ACTION":
                ClaudeStateManager.shared.denyAction(action)
            default:
                break
            }
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
