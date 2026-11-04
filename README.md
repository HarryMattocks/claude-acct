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
- When Anthropic rejects an account for being over its 5-hour or weekly limit (a 429 with `anthropic-ratelimit-unified-7d-status: rejected` or `-5h-status: rejected`), the proxy pauses that account until its reset time. It retries the same request on the next account, so the client never sees the error.
- Running close to a limit (`allowed_warning`, up to 99%) does not trigger a switch. Only a real rejection does, so every account is used up before the next one starts.
- After the reset, new conversations go back to the primary account.

This has been tested against a real exhausted account. The proxy got the 429 from Anthropic, finished the request on the second account, and paused the first until the exact reset time Anthropic reported:

```
$ claude-acct list
  ON   work@example.com      priority=100  out of usage, back 2026-11-08T17:00Z
  ON   personal@example.com  priority=0    active
```

Only clients that send their requests **through the proxy** get failover. A Claude Code session using its own login talks to Anthropic directly and stops at the limit as usual. See [Which sessions use the proxy](#which-sessions-use-the-proxy).

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
claude-acct t3 --all --default
```

This is the recommended setup. It:

- Routes T3 Code's built-in **Claude** instance through the proxy, so every Claude thread, old and new, gets failover. The instance keeps its normal config directory (`~/.claude`), so your CLAUDE.md, skills, settings and thread history stay as they are.
- Adds a separate **Claude (proxy)** instance with its own config directory (`~/.claude-proxy`).
- Adds the proxy as a usage hub, and makes **Claude** the default.

T3 Code reloads `settings.json` on its own, and a backup is written next to it first. Undo it all with `claude-acct t3 --remove`.

Without `--all`, only the **Claude (proxy)** instance uses the proxy, and threads on the built-in **Claude** instance keep using your CLI login. T3 Code can't move an existing thread to an instance with a different config directory, so those threads won't fail over.

> [!NOTE]
> When a Claude Code session goes through the proxy, it ignores the claude.ai login, so **claude.ai connectors (Slack, Google Drive, Gmail and so on) are off** in those sessions. If you need connectors in T3 Code, skip `--all` and pick **Claude (proxy)** only for threads that need failover.

`claude-acct t3` writes to T3 Code's internal settings format, which may change between releases. If it stops working, set this up by hand under **Settings → Providers**, either on the built-in **Claude** instance or on a new Claude instance:

| Field | Value |
|---|---|
| CLAUDE_CONFIG_DIR path | empty for the built-in instance, or e.g. `~/.claude-proxy` for a new one |
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:8317` |
| `ANTHROPIC_AUTH_TOKEN` (Sensitive) | `CLIENT_KEY` from `~/.cli-proxy-api/.keys` |
| `ANTHROPIC_API_KEY` | *(empty)* |

For usage tracking, add a hub under **Settings → Providers → Usage providers → Add hub**. Use the URL `http://127.0.0.1:8317` and `MGMT_KEY` as the management key.

### Claude Code CLI

The CLI is left alone: `claude` in your terminal keeps using whatever account it's logged in to (`/login` to change it). To send a single terminal session through the proxy:

```sh
eval "$(claude-acct env)" && claude
```

Don't put `claude-acct env` in your shell profile unless you want every terminal session to go through the proxy.

### Which sessions use the proxy

| Session | Goes through the proxy? | Switch accounts with |
|---|---|---|
| T3 Code, built-in **Claude**, after `t3 --all` | Yes | automatic, or `claude-acct use/primary` |
| T3 Code, **Claude (proxy)** | Yes | automatic, or `claude-acct use/primary` |
| T3 Code, built-in **Claude**, without `--all` | No (CLI login) | `/login` in the Claude CLI |
| Terminal `claude` | No (CLI login) | `/login` |
| Terminal `claude` after `eval "$(claude-acct env)"` | Yes | automatic, or `claude-acct use/primary` |

`claude-acct use`, `primary` and `pool` only change the proxy. They have no effect on sessions that use the CLI login.

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
| `claude-acct t3 [--all] [--default]` | Set up T3 Code (see above); `--remove` undoes it |
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

## Troubleshooting

**A thread hit the limit and didn't switch.** That thread isn't going through the proxy. Check which instance it's on in T3 Code (see [Which sessions use the proxy](#which-sessions-use-the-proxy)), and run `claude-acct t3 --all` if it's the built-in **Claude**. To get unstuck right away, run `/login` in the Claude CLI with the other account.

**`claude-acct usage` shows 100% but the account wasn't paused.** Usage is rounded. Anthropic keeps accepting requests at 99% (`allowed_warning`), and the account is only paused when Anthropic actually rejects a request.

**`claude-acct list` shows an error that isn't about usage.** The login probably needs renewing. Run `claude-acct login` with that account.

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
