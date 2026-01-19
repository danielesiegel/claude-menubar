import Foundation
import AppKit
import Combine

enum TaskStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "arrow.trianglehead.clockwise"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        }
    }
}

import SwiftUI

struct ClaudeTask: Identifiable, Codable {
    let id: UUID
    var content: String
    var status: TaskStatus
    var activeForm: String?

    init(id: UUID = UUID(), content: String, status: TaskStatus, activeForm: String? = nil) {
        self.id = id
        self.content = content
        self.status = status
        self.activeForm = activeForm
    }
}

enum ActionType: String, Codable {
    case bash = "Bash Command"
    case write = "Write File"
    case edit = "Edit File"
    case mcp = "MCP Tool"
    case other = "Action"

    var icon: String {
        switch self {
        case .bash: return "terminal"
        case .write: return "doc.badge.plus"
        case .edit: return "pencil"
        case .mcp: return "server.rack"
        case .other: return "questionmark.circle"
        }
    }
}

struct PendingAction: Identifiable, Codable {
    let id: UUID
    let type: ActionType
    let description: String
    let timestamp: Date
    let toolName: String?

    init(id: UUID = UUID(), type: ActionType, description: String, toolName: String? = nil) {
        self.id = id
        self.type = type
        self.description = description
        self.timestamp = Date()
        self.toolName = toolName
    }
}

struct ClaudeState: Codable {
    var isActive: Bool
    var tasks: [ClaudeTask]
    var pendingActions: [PendingAction]
    var sessionId: String?
    var terminalApp: String?
}

class ClaudeStateManager: ObservableObject {
    static let shared = ClaudeStateManager()

    @Published var isClaudeActive = false
    @Published var currentTasks: [ClaudeTask] = []
    @Published var pendingActions: [PendingAction] = []
    @Published var currentSessionId: String?

    private var processMonitorTimer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var stateFileURL: URL
    private var commandFileURL: URL
    private let fileManager = FileManager.default

    private init() {
        // Setup state directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let stateDir = appSupport.appendingPathComponent("ClaudeMenuBar", isDirectory: true)

        try? fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)

        stateFileURL = stateDir.appendingPathComponent("claude_state.json")
        commandFileURL = stateDir.appendingPathComponent("commands.json")

        // Create empty state file if needed
        if !fileManager.fileExists(atPath: stateFileURL.path) {
            let emptyState = ClaudeState(isActive: false, tasks: [], pendingActions: [])
            saveState(emptyState)
        }

        loadState()
    }

    func startMonitoring() {
        // Monitor for Claude processes
        startProcessMonitoring()

        // Watch for state file changes (from hooks)
        startFileWatching()
    }

    func stopMonitoring() {
        processMonitorTimer?.invalidate()
        processMonitorTimer = nil
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    // MARK: - Process Monitoring

    private func startProcessMonitoring() {
        // Check immediately
        checkForClaudeProcesses()

        // Then check periodically
        processMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForClaudeProcesses()
        }
    }

    private func checkForClaudeProcesses() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid,command"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let isActive = output.contains("claude") &&
                    (output.contains("Terminal") || output.contains("ghostty") ||
                     output.contains("node") || output.contains("claude-code"))

                DispatchQueue.main.async { [weak self] in
                    let wasActive = self?.isClaudeActive ?? false
                    self?.isClaudeActive = isActive

                    if wasActive != isActive {
                        NotificationCenter.default.post(name: .claudeStateDidChange, object: nil)
                    }
                }
            }
        } catch {
            print("Error checking processes: \(error)")
        }
    }

    // MARK: - File Watching

    private func startFileWatching() {
        let fd = open(stateFileURL.path, O_EVTONLY)
        guard fd != -1 else { return }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        fileWatcher?.setEventHandler { [weak self] in
            self?.loadState()
        }

        fileWatcher?.setCancelHandler {
            close(fd)
        }

        fileWatcher?.resume()
    }

    // MARK: - State Management

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(ClaudeState.self, from: data) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentTasks = state.tasks
            self?.pendingActions = state.pendingActions
            self?.currentSessionId = state.sessionId

            if state.isActive != self?.isClaudeActive {
                self?.isClaudeActive = state.isActive
                NotificationCenter.default.post(name: .claudeStateDidChange, object: nil)
            }
        }
    }

    private func saveState(_ state: ClaudeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFileURL)
    }

    // MARK: - Action Handling

    func approveAction(_ action: PendingAction) {
        // Write command to file for hook to pick up
        let command = ["action": "approve", "id": action.id.uuidString]
        if let data = try? JSONEncoder().encode(command) {
            try? data.write(to: commandFileURL)
        }

        // Send keystroke to terminal (simulates pressing 'y')
        sendKeystrokeToTerminal("y\n")

        // Remove from pending
        pendingActions.removeAll { $0.id == action.id }
    }

    func denyAction(_ action: PendingAction) {
        // Write command to file
        let command = ["action": "deny", "id": action.id.uuidString]
        if let data = try? JSONEncoder().encode(command) {
            try? data.write(to: commandFileURL)
        }

        // Send keystroke to terminal (simulates pressing 'n')
        sendKeystrokeToTerminal("n\n")

        // Remove from pending
        pendingActions.removeAll { $0.id == action.id }
    }

    private func sendKeystrokeToTerminal(_ keystroke: String) {
        // Use AppleScript to send keystroke to frontmost terminal
        let script = """
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
            if frontApp is "Terminal" or frontApp is "ghostty" then
                keystroke "\(keystroke)"
            end if
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - Hook Handlers (called from CLI)

    func handleTaskUpdate(tasks: [ClaudeTask]) {
        DispatchQueue.main.async { [weak self] in
            self?.currentTasks = tasks
        }
    }

    func handlePermissionRequest(action: PendingAction) {
        DispatchQueue.main.async { [weak self] in
            self?.pendingActions.append(action)
            NotificationCenter.default.post(name: .claudePermissionRequest, object: action)
        }
    }

    func handleTaskComplete() {
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: .claudeTaskComplete, object: nil)
        }
    }
}

// MARK: - IPC Handler for receiving hook events

class IPCHandler {
    static let shared = IPCHandler()

    private var server: CFMessagePort?
    private let portName = "com.claudemenubar.ipc"

    func startListening() {
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        server = CFMessagePortCreateLocal(
            nil,
            portName as CFString,
            { (port, msgid, data, info) -> Unmanaged<CFData>? in
                guard let data = data as Data?,
                      let message = try? JSONDecoder().decode(IPCMessage.self, from: data) else {
                    return nil
                }

                DispatchQueue.main.async {
                    IPCHandler.shared.handleMessage(message)
                }

                return nil
            },
            &context,
            nil
        )

        if let server = server {
            let runLoopSource = CFMessagePortCreateRunLoopSource(nil, server, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    private func handleMessage(_ message: IPCMessage) {
        switch message.type {
        case .taskUpdate:
            if let tasks = message.tasks {
                ClaudeStateManager.shared.handleTaskUpdate(tasks: tasks)
            }
        case .permissionRequest:
            if let action = message.action {
                ClaudeStateManager.shared.handlePermissionRequest(action: action)
            }
        case .taskComplete:
            ClaudeStateManager.shared.handleTaskComplete()
        case .stateChange:
            NotificationCenter.default.post(name: .claudeStateDidChange, object: nil)
        }
    }
}

enum IPCMessageType: String, Codable {
    case taskUpdate
    case permissionRequest
    case taskComplete
    case stateChange
}

struct IPCMessage: Codable {
    let type: IPCMessageType
    var tasks: [ClaudeTask]?
    var action: PendingAction?
}
