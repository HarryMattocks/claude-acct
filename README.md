# claude-acct

Use several Claude subscription accounts from one Claude Code setup, with automatic failover when one runs out of usage.

`claude-acct` is a thin macOS wrapper around [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI). It installs and configures the proxy, gives you a small CLI to choose which account is used, and sends a macOS notification when a login breaks or an account hits its limit. It also has a one-command setup for [T3 Code](https://github.com/pingdotgg/t3code).

```
$ claude-acct usage
work@example.com (priority 100)
  weekly_all: 88%  resets 2026-11-08T17:00Z
personal@example.com (priority 0)
  weekly_all: 0%  resets 2026-11-06T02:00Z
```

> [!WARNING]
> Sending a Claude subscription login through a third-party proxy may violate Anthropic's [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) and could get an account restricted. Read the terms and decide for yourself before using this. This project is not affiliated with Anthropic.

## How it works

```
Claude Code / T3 Code ──► CLIProxyAPI (127.0.0.1:8317) ──► account A  (priority 100)
                                                      └──► account B  (priority 0)
```

- The proxy is set to `fill-first` routing with session affinity. Every request goes to the highest-priority account that is available, and a conversation stays on one account.
- When Anthropic rejects an account for being over its 5-hour or weekly limit (a 429 with `anthropic-ratelimit-unified-*-status: rejected`), the proxy pauses that account until its reset time. It retries the same request on the next account, so the client never sees the error.
- Running close to a limit (`allowed_warning`) does not trigger a switch. Only a real rejection does.
- After the reset, new conversations go back to the primary account.

## Requirements

- macOS with [Homebrew](https://brew.sh)
- `jq` and `cliproxyapi` (both installed by `install.sh` if missing)
- One or more Claude Pro/Max accounts

## Install

```sh
git clone https://github.com/HarryMattocks/claude-acct.git
cd claude-acct
./install.sh
```

The installer:

1. Installs `cliproxyapi` and `jq` with Homebrew.
2. Generates a client key and a management key in `~/.cli-proxy-api/.keys` (mode 600).
3. Writes a proxy config bound to `127.0.0.1` only and starts it as a Homebrew service.
4. Installs `claude-acct` and `claude-acct-watch` to `~/.local/bin`.
5. Installs a LaunchAgent that runs `claude-acct-watch` every 15 minutes.

Options: `--port N`, `--bin-dir DIR`, `--no-watch`, `--force-config`. If you already have your own CLIProxyAPI config, it is kept unless you pass `--force-config`.

Then add your accounts:

```sh
claude-acct login          # sign in to account A in the browser
claude-acct login          # again for account B — use a private window so the browser doesn't reuse A
claude-acct primary work@  # prefer A, fail over to B
```

## Use it

### T3 Code

```sh
claude-acct t3 --default
```

This adds a **Claude (proxy)** provider instance to T3 Code and makes it the default. It also adds the proxy as a usage hub. The instance uses its own config directory (`~/.claude-proxy`), so it doesn't conflict with a normal Claude login. T3 Code reloads `settings.json` on its own, and a backup is written next to it first.

`claude-acct t3` writes to T3 Code's internal settings format, which may change between releases. If it stops working, add the instance by hand under **Settings → Providers → Add instance → Claude**:

| Field | Value |
|---|---|
| CLAUDE_CONFIG_DIR path | `~/.claude-proxy` |
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:8317` |
| `ANTHROPIC_AUTH_TOKEN` (Sensitive) | `CLIENT_KEY` from `~/.cli-proxy-api/.keys` |
| `ANTHROPIC_API_KEY` | *(empty)* |

For usage tracking, add a hub under **Settings → Providers → Usage providers → Add hub**. Use the URL `http://127.0.0.1:8317` and `MGMT_KEY` as the management key.

### Claude Code CLI or anything else

```sh
eval "$(claude-acct env)"
CLAUDE_CONFIG_DIR=~/.claude-proxy claude
```

## Commands

| Command | What it does |
|---|---|
| `claude-acct list` | Accounts, priority, and proxy status |
| `claude-acct usage` | Live plan usage for each account, from Anthropic |
| `claude-acct primary <account>` | Enable all accounts, prefer `<account>`, fail over to the rest |
| `claude-acct use <account>` | Send everything to `<account>` only; the others are disabled |
| `claude-acct pool` | Enable all accounts |
| `claude-acct login` | Add an account (browser OAuth) |
| `claude-acct env` | Print `ANTHROPIC_*` exports for the proxy |
| `claude-acct t3 [--default]` | Add the proxy instance to T3 Code |
| `claude-acct-watch test` | Send a test notification |

`<account>` is any unique part of the email address.

Changes apply from the next request. Existing conversations keep working because the client's config directory doesn't change.

## Notifications

`claude-acct-watch` runs every 15 minutes and notifies only when something changes:

| Notification | Meaning |
|---|---|
| Login problem / Login rejected | The proxy can't renew the login, or Anthropic returns 401/403. Run `claude-acct login`. |
| Out of usage | The account hit a limit and requests moved to the next account. |
| CLIProxyAPI isn't responding | Run `brew services restart cliproxyapi`. |
| Back to normal | An account that had a problem is healthy again. |

Notifications are sent with `osascript`. If `claude-acct-watch test` shows nothing, allow **Script Editor** in System Settings → Notifications. The log is at `~/.cli-proxy-api/watch.log`.

## Files

| Path | Contents |
|---|---|
| `~/.cli-proxy-api/` | Account logins (CLIProxyAPI auth files), `.keys`, watch state and log |
| `$(brew --prefix)/etc/cliproxyapi.conf` | Proxy config |
| `~/Library/LaunchAgents/io.github.claude-acct.watch.plist` | Notification agent |

## Uninstall

```sh
./uninstall.sh
```

This removes the scripts and the LaunchAgent and stops the proxy. Your logins and config are left in place; the script prints how to remove them.

## Credits

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) does the OAuth, routing, and failover.
- [T3 Code](https://github.com/pingdotgg/t3code)

## License

MIT
