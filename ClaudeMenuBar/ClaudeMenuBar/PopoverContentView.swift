import SwiftUI

struct PopoverContentView: View {
    @EnvironmentObject var stateManager: ClaudeStateManager
    @EnvironmentObject var notificationManager: NotificationManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Claude Code")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                StatusIndicator(isActive: stateManager.isClaudeActive)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Current Tasks Section
                    TasksSection(tasks: stateManager.currentTasks)

                    Divider()
                        .padding(.horizontal, 16)

                    // Pending Actions Section
                    if !stateManager.pendingActions.isEmpty {
                        PendingActionsSection(actions: stateManager.pendingActions)

                        Divider()
                            .padding(.horizontal, 16)
                    }

                    // Settings Section
                    SettingsSection()
                }
                .padding(.vertical, 12)
            }

            Divider()

            // Footer
            HStack {
                Button(action: openSettings) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Text("v1.0.0")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: quitApp) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 320, height: 400)
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

struct StatusIndicator: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(isActive ? "Active" : "Inactive")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

struct TasksSection: View {
    let tasks: [ClaudeTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Current Tasks", icon: "list.bullet")

            if tasks.isEmpty {
                EmptyStateView(message: "No active tasks")
            } else {
                ForEach(tasks) { task in
                    TaskRow(task: task)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct TaskRow: View {
    let task: ClaudeTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status.icon)
                .font(.system(size: 12))
                .foregroundColor(task.status.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.content)
                    .font(.system(size: 12))
                    .lineLimit(2)

                if let activeForm = task.activeForm {
                    Text(activeForm)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct PendingActionsSection: View {
    let actions: [PendingAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Pending Approval", icon: "hand.raised")

            ForEach(actions) { action in
                PendingActionRow(action: action)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct PendingActionRow: View {
    let action: PendingAction
    @EnvironmentObject var stateManager: ClaudeStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: action.type.icon)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text(action.type.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
                Spacer()
            }

            Text(action.description)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Button(action: { stateManager.denyAction(action) }) {
                    Text("Deny")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: { stateManager.approveAction(action) }) {
                    Text("Approve")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

struct SettingsSection: View {
    @EnvironmentObject var notificationManager: NotificationManager
    @AppStorage("showTaskCompletePopover") var showTaskCompletePopover = true
    @AppStorage("enablePermissionNotifications") var enablePermissionNotifications = true
    @AppStorage("enableTouchBar") var enableTouchBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Settings", icon: "slider.horizontal.3")

            SettingsToggle(
                title: "Permission Notifications",
                subtitle: "Show alerts for approve/deny requests",
                icon: "bell.badge",
                isOn: $enablePermissionNotifications
            )

            SettingsToggle(
                title: "Task Complete Popover",
                subtitle: "Show popover when task finishes",
                icon: "checkmark.circle",
                isOn: $showTaskCompletePopover
            )

            SettingsToggle(
                title: "Touch Bar Controls",
                subtitle: "Show approve/deny on Touch Bar",
                icon: "rectangle.bottomhalf.filled",
                isOn: $enableTouchBar
            )
        }
        .padding(.horizontal, 16)
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
        }
        .padding(.vertical, 4)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
    }
}

struct EmptyStateView: View {
    let message: String

    var body: some View {
        HStack {
            Spacer()
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 16)
    }
}

#Preview {
    PopoverContentView()
        .environmentObject(ClaudeStateManager.shared)
        .environmentObject(NotificationManager.shared)
}
