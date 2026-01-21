import Foundation
import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.claudemenubar", category: "ProcessMonitor")

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

struct ClaudeTask: Identifiable, Codable, Equatable {
    let id: String
    var content: String
    var status: TaskStatus
    var activeForm: String?

    init(id: String = UUID().uuidString, content: String, status: TaskStatus, activeForm: String? = nil) {
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
    let id: String
    let type: String  // Raw tool name like "Bash", "Write", "Edit"
    let description: String
    let timestamp: String  // ISO8601 string from hook
    let toolName: String?

    init(id: String = UUID().uuidString, type: String, description: String, timestamp: String? = nil, toolName: String? = nil) {
        self.id = id
        self.type = type
        self.description = description
        self.timestamp = timestamp ?? ISO8601DateFormatter().string(from: Date())
        self.toolName = toolName
    }

    var actionType: ActionType {
        switch type {
        case "Bash": return .bash
        case "Write": return .write
        case "Edit": return .edit
        case let t where t.hasPrefix("mcp__"): return .mcp
        default: return .other
        }
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
    private var transcriptScanTimer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var claudeProjectsDir: URL
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

        // Claude projects directory for transcript scanning
        claudeProjectsDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)

        // Create empty state file if needed
        if !fileManager.fileExists(atPath: stateFileURL.path) {
            let emptyState = ClaudeState(isActive: false, tasks: [], pendingActions: [])
            saveState(emptyState)
        }

        loadState()
    }

    func startMonitoring() {
        logger.notice("startMonitoring() called")
        NSLog("[ClaudeMenuBar] startMonitoring() called")

        // Monitor for Claude processes
        startProcessMonitoring()

        // Watch for state file changes (from hooks)
        startFileWatching()

        // Start transcript scanning for tasks from all sessions
        startTranscriptScanning()
    }

    func stopMonitoring() {
        processMonitorTimer?.invalidate()
        processMonitorTimer = nil
        transcriptScanTimer?.invalidate()
        transcriptScanTimer = nil
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    // MARK: - Process Monitoring

    private func startProcessMonitoring() {
        logger.notice("Starting process monitoring")
        NSLog("[ClaudeMenuBar] Starting process monitoring")

        // Check immediately
        checkForClaudeProcesses()

        // Then check periodically
        processMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForClaudeProcesses()
        }

        // Ensure timer is added to run loop for common modes (menu bar, etc)
        if let timer = processMonitorTimer {
            RunLoop.main.add(timer, forMode: .common)
            NSLog("[ClaudeMenuBar] Timer added to run loop")
        }
    }

    private func checkForClaudeProcesses() {
        // Run on background queue to avoid blocking main thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            // Use tty,comm format to find Claude CLI instances in terminals
            // Claude CLI shows as "claude" with a tty (ttys*) when in Terminal/Ghostty
            task.arguments = ["-eo", "tty,comm"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // Check for claude processes with a TTY (running in terminal)
                    // Lines look like: "ttys000  claude" or "ttys001  claude"
                    let lines = output.components(separatedBy: "\n")

                    // Find matching lines for debugging
                    let matchingLines = lines.filter { line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        return trimmed.contains("ttys") && trimmed.hasSuffix("claude")
                    }

                    let isActive = !matchingLines.isEmpty
                    NSLog("[ClaudeMenuBar] Check: found \(matchingLines.count) Claude instances, isActive=\(isActive)")

                    if !matchingLines.isEmpty {
                        logger.notice("Found Claude CLI instances: \(matchingLines.joined(separator: ", "))")
                        NSLog("[ClaudeMenuBar] Found: \(matchingLines.joined(separator: ", "))")
                    }

                    DispatchQueue.main.async {
                        let wasActive = self?.isClaudeActive ?? false
                        self?.isClaudeActive = isActive

                        if wasActive != isActive {
                            logger.notice("State changed: \(wasActive) -> \(isActive)")
                            NSLog("[ClaudeMenuBar] State changed: \(wasActive) -> \(isActive)")
                            NotificationCenter.default.post(name: .claudeStateDidChange, object: nil)
                        }
                    }
                }
            } catch {
                logger.error("Error checking processes: \(error.localizedDescription)")
                NSLog("[ClaudeMenuBar] Error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Transcript Scanning

    private func startTranscriptScanning() {
        NSLog("[ClaudeMenuBar] Starting transcript scanning")

        // Scan immediately
        scanTranscripts()

        // Then scan periodically (every 3 seconds)
        transcriptScanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scanTranscripts()
        }

        if let timer = transcriptScanTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func scanTranscripts() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var allTasks: [ClaudeTask] = []

            // Find recently modified transcript files (within last 2 hours)
            let twoHoursAgo = Date().addingTimeInterval(-7200)

            guard let enumerator = self.fileManager.enumerator(
                at: self.claudeProjectsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }

                // Check if recently modified
                if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modDate = attrs.contentModificationDate,
                   modDate > twoHoursAgo {

                    // Parse this transcript for TodoWrite
                    if let tasks = self.parseTranscriptForTasks(fileURL) {
                        allTasks.append(contentsOf: tasks)
                    }
                }
            }

            // Update tasks on main thread
            DispatchQueue.main.async {
                // Only update if tasks changed (compare by count and content)
                let currentIds = Set(self.currentTasks.map { $0.id })
                let newIds = Set(allTasks.map { $0.id })

                if currentIds != newIds || allTasks.count != self.currentTasks.count {
                    self.currentTasks = allTasks
                    NSLog("[ClaudeMenuBar] Updated tasks from transcripts: \(allTasks.count) tasks")
                }
            }
        }
    }

    private func parseTranscriptForTasks(_ fileURL: URL) -> [ClaudeTask]? {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Find the last TodoWrite entry by reading lines in reverse
        let lines = content.components(separatedBy: "\n").reversed()

        for line in lines {
            guard !line.isEmpty,
                  line.contains("TodoWrite"),
                  let lineData = line.data(using: .utf8) else {
                continue
            }

            // Try to parse the line as JSON
            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else {
                continue
            }

            // Find TodoWrite tool use in content
            for item in content {
                guard let name = item["name"] as? String,
                      name == "TodoWrite",
                      let input = item["input"] as? [String: Any],
                      let todos = input["todos"] as? [[String: Any]] else {
                    continue
                }

                // Convert to ClaudeTask array
                var tasks: [ClaudeTask] = []
                for todo in todos {
                    if let todoContent = todo["content"] as? String,
                       let status = todo["status"] as? String {
                        let taskStatus: TaskStatus
                        switch status {
                        case "in_progress": taskStatus = .inProgress
                        case "completed": taskStatus = .completed
                        default: taskStatus = .pending
                        }

                        let task = ClaudeTask(
                            id: todo["id"] as? String ?? UUID().uuidString,
                            content: todoContent,
                            status: taskStatus,
                            activeForm: todo["activeForm"] as? String
                        )
                        tasks.append(task)
                    }
                }

                if !tasks.isEmpty {
                    return tasks
                }
            }
        }

        return nil
    }

    // MARK: - File Watching

    private func startFileWatching() {
        NSLog("[ClaudeMenuBar] Starting file watcher for: \(stateFileURL.path)")

        let fd = open(stateFileURL.path, O_EVTONLY)
        guard fd != -1 else {
            NSLog("[ClaudeMenuBar] Failed to open file for watching")
            return
        }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        fileWatcher?.setEventHandler { [weak self] in
            NSLog("[ClaudeMenuBar] File change detected!")
            self?.loadState()
        }

        fileWatcher?.setCancelHandler {
            close(fd)
        }

        fileWatcher?.resume()
        NSLog("[ClaudeMenuBar] File watcher started")
    }

    // MARK: - State Management

    private func loadState() {
        NSLog("[ClaudeMenuBar] loadState() called")

        guard let data = try? Data(contentsOf: stateFileURL) else {
            NSLog("[ClaudeMenuBar] Failed to read state file")
            return
        }

        guard let state = try? JSONDecoder().decode(ClaudeState.self, from: data) else {
            NSLog("[ClaudeMenuBar] Failed to decode state JSON")
            if let jsonString = String(data: data, encoding: .utf8) {
                NSLog("[ClaudeMenuBar] Raw JSON: \(jsonString.prefix(200))")
            }
            return
        }

        NSLog("[ClaudeMenuBar] Loaded state: \(state.tasks.count) tasks, \(state.pendingActions.count) pending actions")

        DispatchQueue.main.async { [weak self] in
            // Only load tasks, pending actions, and session ID from file
            // The process monitor is the authoritative source for isClaudeActive
            self?.currentTasks = state.tasks
            self?.pendingActions = state.pendingActions
            self?.currentSessionId = state.sessionId

            NSLog("[ClaudeMenuBar] State applied to manager")

            // Notify if pending actions changed (for UI update)
            if !state.pendingActions.isEmpty {
                NotificationCenter.default.post(name: .claudePermissionRequest, object: nil)
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
        let command = ["action": "approve", "id": action.id]
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
        let command = ["action": "deny", "id": action.id]
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
