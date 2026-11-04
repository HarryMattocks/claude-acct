#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
usage: ./install.sh [--port N] [--bin-dir DIR] [--no-watch] [--force-config]

  --port N          proxy port (default 8317)
  --bin-dir DIR     where to install claude-acct scripts (default ~/.local/bin)
  --no-watch        skip the background notification agent
  --force-config    overwrite an existing CLIProxyAPI config not written by claude-acct
EOF
}

PORT=8317 BIN_DIR="$HOME/.local/bin" WATCH=true FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift ;;
    --bin-dir) BIN_DIR="$2"; shift ;;
    --no-watch) WATCH=false ;;
    --force-config) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
  shift
done

SRC="$(cd "$(dirname "$0")" && pwd)"
AUTH_DIR="$HOME/.cli-proxy-api"
KEYS="$AUTH_DIR/.keys"
LABEL="io.github.claude-acct.watch"
MARKER="# managed by claude-acct"

[[ "$(uname)" == Darwin ]] || { echo "claude-acct currently supports macOS only." >&2; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh" >&2; exit 1; }
for dep in jq cliproxyapi; do
  command -v "$dep" >/dev/null || { echo "==> brew install $dep"; brew install "$dep"; }
done

CONF="$(brew --prefix)/etc/cliproxyapi.conf"

mkdir -p "$AUTH_DIR" && chmod 700 "$AUTH_DIR"
if [[ ! -f "$KEYS" ]]; then
  ( umask 077
    printf 'CLIENT_KEY=%s\nMGMT_KEY=%s\nPROXY_URL=%s\n' \
      "sk-claude-acct-$(openssl rand -hex 24)" "$(openssl rand -hex 24)" "http://127.0.0.1:$PORT" > "$KEYS" )
  echo "==> generated proxy keys in $KEYS"
fi
source "$KEYS"
grep -q '^PROXY_URL=' "$KEYS" || echo "PROXY_URL=http://127.0.0.1:$PORT" >> "$KEYS"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:$PORT}"
PORT="${PROXY_URL##*:}"

write_config() {
  [[ -f "$CONF" ]] && cp "$CONF" "$CONF.bak-$(date +%Y%m%d%H%M%S)"
  ( umask 077; cat > "$CONF" <<EOF
$MARKER
config-version: 8
server:
  host: "127.0.0.1"
  port: $PORT
management:
  allow-remote: false
  secret-key: "$MGMT_KEY"
oauth:
  auth-dir: "$AUTH_DIR"
access:
  api-keys:
    - "$CLIENT_KEY"
routing:
  strategy: "fill-first"
  session-affinity: true
  session-affinity-ttl: "1h"
  session-affinity-rebind-on: "quota"
EOF
  )
  echo "==> wrote $CONF"
}

if [[ ! -f "$CONF" ]] || grep -qF "$MARKER" "$CONF" || grep -q 'your-api-key-1' "$CONF" || $FORCE; then
  write_config
else
  echo "==> keeping existing $CONF (not written by claude-acct; use --force-config to replace)"
fi

echo "==> starting CLIProxyAPI"
brew services restart cliproxyapi >/dev/null
for _ in $(seq 1 30); do
  curl -fsS -o /dev/null -H "Authorization: Bearer $MGMT_KEY" "$PROXY_URL/v0/management/auth-files" 2>/dev/null && break
  sleep 1
done
curl -fsS -o /dev/null -H "Authorization: Bearer $MGMT_KEY" "$PROXY_URL/v0/management/auth-files" ||
  { echo "CLIProxyAPI did not come up on $PROXY_URL — check: brew services info cliproxyapi" >&2; exit 1; }

mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/claude-acct" "$SRC/bin/claude-acct-watch" "$BIN_DIR/"
echo "==> installed claude-acct and claude-acct-watch to $BIN_DIR"
[[ ":$PATH:" == *":$BIN_DIR:"* ]] || echo "    note: $BIN_DIR is not on your PATH"

if $WATCH; then
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  mkdir -p "$(dirname "$PLIST")"
  sed -e "s#__LABEL__#$LABEL#" -e "s#__BIN__#$BIN_DIR/claude-acct-watch#" -e "s#__LOG__#$AUTH_DIR/watch.log#" \
    "$SRC/launchd/watch.plist" > "$PLIST"
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "==> notification agent installed (checks every 15 min)"
fi

cat <<EOF

Done. Next:
  claude-acct login                 # once per Claude account (use a private window for the 2nd)
  claude-acct primary <email>       # prefer one account, fail over to the others
  claude-acct t3 --default          # optional: add "Claude (proxy)" to T3 Code
  eval "\$(claude-acct env)"          # or point any Claude Code session at the proxy
  claude-acct-watch test            # check macOS notifications reach you
EOF
