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

## sync: mirror a *local* codespace to a remote

`codespace sync` is the other direction: you have a normal **local** codespace
(worktree or clone) and want to run/continue it on a remote host (more CPU, a
GPU, docker, …). it mirrors your codespace to the host and is **re-runnable** —
sync again after more local (or remote) work and it converges.

```sh
codespace sync [<branch>|<path>] -r [host]   # first sync: pick the host
codespace sync                               # later: host remembered (marker)
```

`-r [host]` resolves like create (`$CS_DEFAULT_REMOTE` / `.codespace/remote`).
the first successful sync remembers the target in a git-excluded
`.codespace/sync` marker, so subsequent `codespace sync` needs no `-r`.

### commit-first model

sync works at **commit** granularity — committed work is the unit that's
mirrored. integration is keyed on the **last synced commit** (recorded in the
marker) as the fork point both sides last agreed on, so a history rewrite
(amend / squash / rebase / reset) is understood as a rewrite, not as a brand-new
diverging commit. from what each side did since that point:

- **only local moved** (incl. a rewrite while the remote sat still) → local
  wins: the remote fast-forwards, or is reset to local `HEAD` on a rewrite.
- **only the remote moved** → the remote wins: local fast-forwards, or is reset
  to the remote tip on a remote rewrite (your old local tip is backed up first).
- **both moved** → genuinely ambiguous. interactively you're prompted
  `[r]ebase  [o]urs  [t]heirs  [a]bort` (rebase is the default, so neither
  side's progress is lost; resolve any conflict in your local checkout, then
  re-run). non-interactively sync **aborts** rather than silently rewriting
  history — re-run interactively or pass `--ours` / `--theirs`.

history moves over plain ssh: local fetches the remote worktree and hands the
remote its canonical tip via a holding ref in the remote base repo, which the
remote worktree reconciles onto (fast-forward / rebase, else a `reset --hard`
that first stashes the old tip in a hidden `refs/cs-sync/backup/...` ref).

- `--ours` forces **local** `HEAD` to win: the remote is reset to it (old remote
  tip backed up). use it to resolve a both-moved divergence in local's favor.
- `--theirs` forces the **remote** tip to win: local is reset to it (old local
  tip backed up under `refs/cs-sync/backup/local/...`). uses the host resolved
  for this run (`-r [host]` / marker / default).

### uncommitted changes

by default (`--mode all`) sync mirrors your uncommitted working tree too, not
just commits (gitignored paths don't count). how depends on what's available:

- **live session** — if `mutagen` is installed, dirty work is mirrored through a
  persistent two-way session (see below). this is the default when present.
- **one-shot overlay** (`--once`) — a dependency-free one-shot `rsync` of your
  local working tree onto the remote (honoring `.gitignore`). only allowed when
  the remote is clean, so it can't clobber independent remote work.

if a one-shot overlay would clobber **uncommitted work on the remote**, sync
refuses; interactively it offers:

```
[r]etry  [c]ommits-only  [a]bort
```

- **commits-only** (`--mode commits`) — sync just the commit history and leave
  the uncommitted tree untouched (local-only). to turn dirty work into history,
  `git commit` it yourself, then sync.
- non-interactive runs (agents/CI) don't prompt — reconcile the remote, install
  mutagen, or pass `--mode commits`.

> note: a one-shot overlay leaves the remote with uncommitted changes, so the
> next plain `codespace sync` will see the remote as dirty. commit, or overlay
> again. the persistent live mode (below) avoids this.

`--dry-run` prints the plan and mutates nothing.

### live (uncommitted) sync

for uncommitted work you'd rather keep mirrored continuously (edit here, run
there, no manual re-sync), `codespace sync --watch` keeps a persistent,
bidirectional file sync running so both trees converge as you type — committed
*and* uncommitted, no divergence until you commit.

```sh
codespace sync --watch        # start (or re-attach to) a live session
codespace sync --stop-watch   # tear it down
```

- it's backed by [mutagen](https://mutagen.io) — an **optional** dependency
  we only fetch when you opt in. on first use we check both ends and offer to
  install it locally and on the remote; decline and sync falls back to the
  one-shot overlay.
- gitignored paths (and `.git`, `open`, `.codespace/`) are excluded, so heavy
  dirs like `node_modules/` never sync.
- once started it's **sticky**: later plain `codespace sync` runs keep it live
  (the `.codespace/sync` marker records `sync_mode=live`), and `codespace ls`
  annotates the codespace `(live-sync)`.
- **committing during a live session** is safe — including partial commits. the
  session is frozen, the non-committing side's remainder is stashed, the commit
  integrates as history (both ways), then the remainder is restored and the
  session resumes. nothing uncommitted is lost. a `post-commit` hook triggers
  this automatically; concurrent syncs are serialized by a per-codespace lock.
- genuine two-way edit conflicts are surfaced and you're prompted to resolve
  them manually or via a *commit-both-ends* bridge (commit each side, then
  reconcile as a normal rebase conflict).

### opening the remote directly

`codespace open -r [host]` (or `edit -r`) opens a *local* codespace's **remote**
counterpart: it syncs first (provision + integrate + start live sync), then
opens over ssh-remote. host resolves from the `.codespace/sync` marker if
omitted. this is the one-command "send me to the big machine, keep my edits
flowing" path.

### stacks

point `codespace sync` at a stack (run it from inside a `stack_<branch>` dir, or
pass the branch/path) and it syncs the whole stack: the host is prepared once,
then each repo is commit-synced independently (same model as above), the stack
root's loose top-level files are rsync'd over, and a `kind=stack` marker is
written at the stack root. a conflict in one repo is reported at the end and
doesn't block the others — resolve it in that repo and re-run.

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
