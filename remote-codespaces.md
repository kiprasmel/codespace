# working in remote codespaces

a *remote* codespace lives on a remote ssh host instead of your laptop. the
real worktree/clone is created on the host; locally you only get a thin **stub**
that tracks it, and your editor opens the remote folder over SSH-Remote.

this is handy for heavy builds, GPUs, always-on boxes, or just keeping your
laptop cool — while still using `codespace` conventions and your editor as if
it were local.

> for the full flag reference see `codespace -h` (the `-r/--remote` flag) and
> `codespace stack -h`. this doc is the workflow + the editor-reconnection bits
> that don't fit in `--help`.

## create one

```sh
# single-repo worktree on the remote
codespace <branch> -r [host]

# a multi-repo stack on the remote
codespace stack create <branch> -r [host]
```

if you omit `[host]`, it's resolved in this order (first hit wins):

1. `$CS_DEFAULT_REMOTE`
2. `$CODESPACE_CONFIG_ROOT/<org>/<repo>/.codespace/remote` (per-repo)
3. `$CODESPACE_CONFIG_ROOT/<org>/.codespace/remote` (per-org)

the `<host>` is any ssh target (`user@host`, or a `Host` alias from
`~/.ssh/config` — recommended, see below).

### path layout (single mapping rule)

```
local   $HOME/X                     <->  remote  $HOME/codespace/X
local   $CODESPACE_CONFIG_ROOT/<id> <->  remote  $HOME/codespace-config/<id>
```

so a local `~/org/repo_feat` stub maps to `~/codespace/org/repo_feat` on the
host.

### what happens on create

1. installs the `codespace` scripts on the host (`~/.local/bin/`) and probes for
   deps (`bash git jq rsync`).
2. rsyncs your config dir, creates the worktree/clone, and ships files declared
   via `post-create.link-files-from-{repo,config}` (e.g. `.env`, `AGENTS.md`).
3. runs `.codespace/remote-bootstrap.sh` (host-level setup) then your
   `post-create`.
4. writes the local stub + a `./open` script, and opens your editor on the
   remote folder.

use `--no-edit` (or `$CS_NO_EDIT`) to skip the editor open — e.g. for agents.

## the local stub

the stub dir (at the usual local path, e.g. `~/org/repo_feat`) is almost empty:

- `.codespace-remote` — marker with `host`, `relpath`, `kind`, `repo_id`,
  `branch`. this is how `find` / `open` / `edit` / `ls` / `rm` locate the remote.
- `open` — a generated executable that re-opens this codespace (see below).

## opening & reopening (after an editor disconnect)

any of these re-open the remote codespace in your editor:

```sh
cd ~/org/repo_feat && ./open      # from the stub dir — no need to remember the branch
codespace open <branch>           # from anywhere inside/near the repo
```

for `cursor` / `code` / `codium` this runs `--remote ssh-remote+<host> <path>`;
for other editors it prints the `ssh` command to get a shell there.

**but the smoothest reconnect is from inside the disconnected window:** run
**`Developer: Reload Window`** (⌘⇧P / Ctrl+Shift+P). the remote server keeps
running, so this re-attaches in place (no new window, keeps saved state — though
it does drop unsaved buffers and terminal scrollback).

## smoother editor reconnection (Cursor / VS Code Remote-SSH)

when your network changes (work ↔ home, sleep/wake, IP change) the TCP tunnel
dies. the remote `cursor-server` keeps running, so reconnecting just re-attaches
— recent Cursor/VS Code even auto-retries for a while. but a stale reconnection
token after a long gap can force a manual `Reload Window`.

a few things make this much less painful:

### 1. ssh keepalive + connection multiplexing (`~/.ssh/config`)

```sshconfig
Host *
    ServerAliveInterval 15
    ServerAliveCountMax 4
    TCPKeepAlive yes
    # optional: reuse one master connection, faster reconnects
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

keeps idle connections alive and detects drops faster. per-host blocks still win
for options they set, so this only fills in the gaps. (`Host *` should go *after*
your specific `Host` blocks.)

### 2. Cursor / VS Code settings (`settings.json`)

```jsonc
"remote.SSH.connectTimeout": 60,            // more tolerance on flaky links
"remote.SSH.maxReconnectionAttempts": null, // retry indefinitely
"window.restoreWindows": "all"              // relaunch reopens the remote workspace
```

(optionally bind `workbench.action.reloadWindow` to a key for one-press reconnect.)

### limitations

- nothing can *resume* a TCP connection killed by an IP change — these settings
  just make detection + reconnect faster and automatic where possible.
- `mosh` is **not** supported by Remote-SSH.
- if drops are frequent, check the host's RAM — the remote server crashes under
  memory pressure (add swap).

## host setup hook: `remote-bootstrap.sh`

place it next to your `post-create` (in the repo's `.codespace/` or your config
dir). it runs **on the host, before** `post-create`, every time (idempotency is
your job). it receives `CS_HOST`, `CS_REPO_ID`, `CS_BRANCH`, `CS_REMOTE_PATH`,
`CS_REMOTE_BASE_REPO`, `CS_POST_CREATE_CONFIG_DIR`. typical uses: install
language runtimes (mise), build a docker image, `apt/brew install`.

`codespace config init` scaffolds a template for it.

## list & remove

```sh
codespace ls                 # remote rows are tagged with @<host>
codespace rm <branch>        # cleans up the remote worktree/clone AND the stub
codespace rm <branch> -f     # skip the (over-ssh) uncommitted/unpushed safety check
```

`rm` checks for uncommitted / untracked / unpushed work on the host before
deleting, just like a local codespace.
