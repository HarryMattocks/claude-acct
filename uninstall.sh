#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${1:-$HOME/.local/bin}"
LABEL="io.github.claude-acct.watch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$BIN_DIR/claude-acct" "$BIN_DIR/claude-acct-watch"
brew services stop cliproxyapi >/dev/null 2>&1 || true

cat <<EOF
Removed claude-acct scripts and the notification agent, and stopped CLIProxyAPI.

Left in place (delete manually if you want them gone):
  ~/.cli-proxy-api/                    Claude logins, proxy keys, watch log
  $(brew --prefix 2>/dev/null || echo /opt/homebrew)/etc/cliproxyapi.conf   proxy config
  brew uninstall cliproxyapi           the proxy itself
  T3 Code: remove "Claude (proxy)" in Settings → Providers
EOF
