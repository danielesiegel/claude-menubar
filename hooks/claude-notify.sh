#!/bin/bash
# Claude MenuBar Hook Script
# Receives JSON via stdin from Claude Code hooks

STATE_DIR="$HOME/Library/Application Support/ClaudeMenuBar"
STATE_FILE="$STATE_DIR/claude_state.json"
LOG_FILE="$STATE_DIR/hook_debug.log"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Read JSON input from stdin
INPUT=$(cat)

# Get event type from argument (PreToolUse, PostToolUse, Stop, Notification)
EVENT_TYPE="$1"

# Parse JSON fields using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Debug logging
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_debug "Event: $EVENT_TYPE, Tool: $TOOL_NAME, Session: $SESSION_ID"

# Function to read current state
read_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo '{"isActive":true,"tasks":[],"pendingActions":[]}'
    fi
}

# Function to send macOS notification
send_notification() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null
}

# Handle different event types
case "$EVENT_TYPE" in
    "PreToolUse")
        log_debug "PreToolUse for tool: $TOOL_NAME"

        # Handle TodoWrite - capture tasks
        if [ "$TOOL_NAME" = "TodoWrite" ]; then
            TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []' 2>/dev/null)
            log_debug "TodoWrite todos: $TODOS"

            if [ -n "$TODOS" ] && [ "$TODOS" != "[]" ] && [ "$TODOS" != "null" ]; then
                # Convert Claude's todo format to our format
                # Use simple string IDs (timestamp-based)
                CONVERTED_TASKS=$(echo "$TODOS" | jq -c '[.[] | {
                    id: ((.id // null) | if . then tostring else ("task-" + (now | tostring)) end),
                    content: .content,
                    status: .status,
                    activeForm: (.activeForm // .content)
                }]' 2>/dev/null)

                log_debug "Converted tasks: $CONVERTED_TASKS"

                # Update state file with new tasks
                CURRENT=$(read_state)
                echo "$CURRENT" | jq --argjson tasks "$CONVERTED_TASKS" --arg sid "$SESSION_ID" \
                    '.tasks = $tasks | .isActive = true | .sessionId = $sid' > "$STATE_FILE"

                log_debug "State updated with tasks"
            fi
        fi

        # Handle permission-requiring tools (Bash, Write, Edit, MCP tools)
        case "$TOOL_NAME" in
            "Bash"|"Write"|"Edit"|mcp__*)
                # Get a description of the action
                case "$TOOL_NAME" in
                    "Bash")
                        DESC=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input.description // "Execute command"' 2>/dev/null | head -c 100)
                        ;;
                    "Write")
                        DESC=$(echo "$INPUT" | jq -r '.tool_input.file_path // "Write file"' 2>/dev/null)
                        ;;
                    "Edit")
                        DESC=$(echo "$INPUT" | jq -r '.tool_input.file_path // "Edit file"' 2>/dev/null)
                        ;;
                    *)
                        DESC="$TOOL_NAME action"
                        ;;
                esac

                log_debug "Permission action: $TOOL_NAME - $DESC"

                # Create pending action
                ACTION_ID=$(uuidgen 2>/dev/null || echo "action-$(date +%s)")
                ACTION_JSON=$(jq -n \
                    --arg id "$ACTION_ID" \
                    --arg type "$TOOL_NAME" \
                    --arg desc "$DESC" \
                    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                    '{id: $id, type: $type, description: $desc, timestamp: $ts}')

                # Update state with pending action
                CURRENT=$(read_state)
                echo "$CURRENT" | jq --argjson action "$ACTION_JSON" --arg sid "$SESSION_ID" \
                    '.pendingActions += [$action] | .isActive = true | .sessionId = $sid' > "$STATE_FILE"

                # Send notification
                send_notification "Claude Code" "$TOOL_NAME: $DESC" "default"
                ;;
        esac
        ;;

    "PostToolUse")
        log_debug "PostToolUse for tool: $TOOL_NAME"

        # Clear pending action for this tool (it's been approved/completed)
        # We can't easily match by ID, so just note completion

        # If TodoWrite completed, the tasks are already set from PreToolUse
        ;;

    "Stop")
        log_debug "Session stopped"

        # Clear tasks and pending actions for this session
        CURRENT=$(read_state)
        echo "$CURRENT" | jq '.tasks = [] | .pendingActions = []' > "$STATE_FILE"

        send_notification "Claude Code" "Session completed" "Glass"
        ;;

    "Notification")
        log_debug "Notification event"
        # Notifications don't typically have structured data we need
        ;;

    *)
        log_debug "Unknown event type: $EVENT_TYPE"
        ;;
esac

exit 0
