#!/bin/bash
# ClaudeMenuBar Uninstaller

set -e

APP_NAME="ClaudeMenuBar"
HOOKS_DIR="$HOME/.claude-menubar"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
APP_SUPPORT_DIR="$HOME/Library/Application Support/ClaudeMenuBar"

echo "╔══════════════════════════════════════╗"
echo "║     ClaudeMenuBar Uninstaller        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Kill the app if running
echo "→ Stopping ClaudeMenuBar..."
pkill -f "$APP_NAME" 2>/dev/null || true

# Remove app bundle
echo "→ Removing application..."
rm -rf "/Applications/$APP_NAME.app"

# Remove hooks directory
echo "→ Removing hooks..."
rm -rf "$HOOKS_DIR"

# Remove app support directory
echo "→ Removing app data..."
rm -rf "$APP_SUPPORT_DIR"

# Remove from login items
echo "→ Removing from login items..."
osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null || true

# Restore Claude settings backup if exists
if [ -f "$CLAUDE_SETTINGS.backup" ]; then
    echo "→ Restoring Claude settings backup..."
    mv "$CLAUDE_SETTINGS.backup" "$CLAUDE_SETTINGS"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Uninstall Complete!              ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "ClaudeMenuBar has been removed."
echo "Your Claude Code hooks have been restored to their backup."
