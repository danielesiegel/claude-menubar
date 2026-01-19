#!/bin/bash
# ClaudeMenuBar Installer
# Installs the menu bar app and configures Claude Code hooks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ClaudeMenuBar"
INSTALL_DIR="/Applications"
HOOKS_DIR="$HOME/.claude-menubar/hooks"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
APP_SUPPORT_DIR="$HOME/Library/Application Support/ClaudeMenuBar"

echo "╔══════════════════════════════════════╗"
echo "║     ClaudeMenuBar Installer          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Check for jq (required for JSON manipulation)
if ! command -v jq &> /dev/null; then
    echo "Installing jq (required for JSON processing)..."
    if command -v brew &> /dev/null; then
        brew install jq
    else
        echo "Error: jq is required. Please install Homebrew and run: brew install jq"
        exit 1
    fi
fi

# Create directories
echo "→ Creating directories..."
mkdir -p "$HOOKS_DIR"
mkdir -p "$APP_SUPPORT_DIR"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

# Copy hook scripts
echo "→ Installing hook scripts..."
cp "$SCRIPT_DIR/hooks/claude-notify.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR/claude-notify.sh"

# Build the app
echo "→ Building ClaudeMenuBar..."
cd "$SCRIPT_DIR/ClaudeMenuBar"

if command -v swift &> /dev/null; then
    swift build -c release

    # Create app bundle
    APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    # Copy executable
    cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

    # Copy Info.plist
    cp "$SCRIPT_DIR/ClaudeMenuBar/ClaudeMenuBar/Info.plist" "$APP_BUNDLE/Contents/"

    # Create PkgInfo
    echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

    echo "✓ App installed to $APP_BUNDLE"
else
    echo "Warning: Swift not found. Please build the app manually in Xcode."
fi

# Configure Claude Code hooks
echo "→ Configuring Claude Code hooks..."

HOOK_SCRIPT="$HOOKS_DIR/claude-notify.sh"

# Create or update Claude settings
if [ -f "$CLAUDE_SETTINGS" ]; then
    # Backup existing settings
    cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.backup"

    # Add hooks to existing settings
    UPDATED_SETTINGS=$(cat "$CLAUDE_SETTINGS" | jq --arg hook "$HOOK_SCRIPT" '
        .hooks = (.hooks // {}) |
        .hooks.PreToolUse = (.hooks.PreToolUse // []) + [{
            "matcher": "Bash|Write|Edit|mcp__.*",
            "hooks": [{"type": "command", "command": $hook + " PreToolUse"}]
        }] |
        .hooks.Stop = (.hooks.Stop // []) + [{
            "matcher": "",
            "hooks": [{"type": "command", "command": $hook + " Stop"}]
        }] |
        .hooks.Notification = (.hooks.Notification // []) + [{
            "matcher": "",
            "hooks": [{"type": "command", "command": $hook + " Notification"}]
        }]
    ')
    echo "$UPDATED_SETTINGS" > "$CLAUDE_SETTINGS"
else
    # Create new settings file
    cat > "$CLAUDE_SETTINGS" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_SCRIPT PreToolUse"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_SCRIPT Stop"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_SCRIPT Notification"
          }
        ]
      }
    ]
  }
}
EOF
fi

echo "✓ Claude Code hooks configured"

# Initialize state file
echo '{"isActive":false,"tasks":[],"pendingActions":[]}' > "$APP_SUPPORT_DIR/claude_state.json"

# Set up login item (optional)
echo ""
read -p "→ Start ClaudeMenuBar at login? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/$APP_NAME.app\", hidden:false}"
    echo "✓ Added to login items"
fi

# Launch the app
echo ""
echo "→ Launching ClaudeMenuBar..."
open "/Applications/$APP_NAME.app" 2>/dev/null || echo "Note: Launch the app manually from /Applications"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Installation Complete!           ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "The Claude icon will appear in your menu bar"
echo "when Claude Code is active in Terminal or Ghostty."
echo ""
echo "To uninstall, run: ./uninstall.sh"
