#!/bin/bash
# Claude MenuBar Hook Script
# Sends events to the ClaudeMenuBar app

STATE_DIR="$HOME/Library/Application Support/ClaudeMenuBar"
STATE_FILE="$STATE_DIR/claude_state.json"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Get event type from environment or argument
EVENT_TYPE="${CLAUDE_HOOK_EVENT:-$1}"
TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
SESSION_ID="${CLAUDE_SESSION_ID:-}"

# Function to update state file
update_state() {
    local is_active="$1"
    local event="$2"

    # Read current state or create default
    if [ -f "$STATE_FILE" ]; then
        current_state=$(cat "$STATE_FILE")
    else
        current_state='{"isActive":false,"tasks":[],"pendingActions":[]}'
    fi

    # Update based on event
    case "$event" in
        "start")
            echo "$current_state" | jq --arg sid "$SESSION_ID" '.isActive = true | .sessionId = $sid' > "$STATE_FILE"
            ;;
        "stop")
            echo "$current_state" | jq '.isActive = false | .tasks = [] | .pendingActions = []' > "$STATE_FILE"
            ;;
        "task_update")
            # Tasks come from stdin as JSON
            if [ -n "$CLAUDE_TASKS" ]; then
                echo "$current_state" | jq --argjson tasks "$CLAUDE_TASKS" '.tasks = $tasks' > "$STATE_FILE"
            fi
            ;;
        "permission_request")
            local action_json=$(cat <<EOF
{
    "id": "$(uuidgen)",
    "type": "$TOOL_NAME",
    "description": "$TOOL_INPUT",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
            echo "$current_state" | jq --argjson action "$action_json" '.pendingActions += [$action]' > "$STATE_FILE"
            send_notification "permission"
            ;;
        "task_complete")
            echo "$current_state" | jq '.tasks = []' > "$STATE_FILE"
            send_notification "complete"
            ;;
    esac
}

# Function to send macOS notification
send_notification() {
    local type="$1"

    case "$type" in
        "permission")
            osascript -e "display notification \"$TOOL_NAME requires approval\" with title \"Claude Code\" subtitle \"Action Required\" sound name \"default\""
            ;;
        "complete")
            osascript -e "display notification \"Task completed successfully\" with title \"Claude Code\" sound name \"Glass\""
            ;;
    esac
}

# Main execution
case "$EVENT_TYPE" in
    "PreToolUse")
        # Check if this tool requires permission
        case "$TOOL_NAME" in
            "Bash"|"Write"|"Edit"|"mcp__"*)
                update_state "true" "permission_request"
                ;;
        esac
        ;;
    "PostToolUse")
        # Tool completed
        ;;
    "Notification")
        # Claude notification event
        update_state "true" "task_update"
        ;;
    "Stop")
        # Claude session stopped
        update_state "false" "stop"
        send_notification "complete"
        ;;
    "Start")
        # Claude session started
        update_state "true" "start"
        ;;
    *)
        echo "Unknown event type: $EVENT_TYPE"
        ;;
esac
