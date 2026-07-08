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

## remote git auth (ssh agent forwarding)

the remote clones/fetches your repos from your code host (GitHub, …) using
**your** ssh key, forwarded from your local `ssh-agent` (`codespace` sets
`ForwardAgent=yes`). the catch: forwarding only presents keys that are *loaded
in the agent*. a key that lives only on disk or in the macOS keychain works for
your **local** `git` (ssh reads it on demand) but is **not** forwarded until
it's `ssh-add`ed — so the remote clone fails with:

```
ERROR: Repository not found.
fatal: Could not read from remote repository.
```

(that message also appears when the forwarded key simply lacks access to the
repo/org — e.g. SSO not authorized.)

**codespace auto-loads a key** before every create/sync, so this usually just
works. it loads, in order:

1. the key(s) you configured (see below),
2. otherwise your default identities (`~/.ssh/id_*`) + the macOS keychain
   (`ssh-add --apple-load-keychain`).

**configuring key(s).** point codespace at the key(s) that can reach your repos
— useful when your key isn't a default identity, or different orgs need
different keys. **multiple keys** are supported (comma- and/or newline-separated;
`#` comments and a leading `~` are fine):

```sh
export CS_SSH_KEY="~/.ssh/gh_work,~/.ssh/gh_personal"   # global, comma-separated
```

or a `ssh-key` file, resolved with the same per-repo/per-org precedence as
`remote` (`.codespace/ssh-key` wins over a root `ssh-key`):

```
$CODESPACE_CONFIG_ROOT/<org>/<repo>/.codespace/ssh-key   # per-repo
$CODESPACE_CONFIG_ROOT/<org>/.codespace/ssh-key          # per-org
```

```sshconfig
# ~/.../myorg/.codespace/ssh-key — one path per line (or comma-separated)
~/.ssh/gh_myorg
```

**verify / troubleshoot:**

```sh
ssh-add -l                          # is a key actually in the agent?
ssh <host> -- ssh -T git@github.com # remote should greet you by GitHub username
```

opt out per-host with `ForwardAgent no` in `~/.ssh/config`.

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

#### picking a winner: `--ours` / `--theirs` / `--hard`

when both sides moved you can decide it non-interactively. by default the pick
is **granular**: sync rebases local's commits onto the remote tip and
auto-resolves only the *conflicting* hunks toward the side you chose — every
non-conflicting change from **both** sides is kept, and no commits are dropped.

- `--ours` — local wins conflicts. (rebase keeps both histories, resolving
  clashes in local's favor; under the hood `git rebase -X theirs`, the inversion
  is git's: the replayed commits are local.)
- `--theirs` — the remote wins conflicts (`git rebase -X ours`).
- `--hard` — escalate to a **wholesale** reset, today's old behavior: the
  winning side's tip replaces the loser's outright, discarding the loser's
  divergent commits (backed up first under `refs/cs-sync/backup/...`). so
  `--ours --hard` resets the remote to local `HEAD`; `--theirs --hard` resets
  local to the remote tip. `--hard` requires `--ours` or `--theirs`.

a conflict git can't auto-resolve granularly (e.g. a modify/delete) stops the
rebase and asks you to finish it (`git rebase --continue`) and re-run; reach for
`--hard` if you'd rather not keep the other side at all.

all of these work in either mode and act purely at the **commit** level — so in
`--mode=dirty` your uncommitted work is never touched by the resolve: it's
stashed before the integration and re-applied afterward (then mirrored as usual
via the live session / one-shot overlay). they only rewrite committed history;
dirty edits on either side are never discarded by a resolve.

### self-healing a broken remote

sync validates that the remote is a healthy checkout before touching it, so an
interrupted or half-provisioned remote (e.g. a first sync whose base-repo clone
couldn't authenticate) no longer cascades into confusing `does not appear to be
a git repository` errors or a false "synced". each repo is classified as:

- **ok** — a valid checkout (and, for a worktree, its base repo is present too);
  sync proceeds.
- **absent** — nothing there yet; sync provisions it from scratch.
- **broken** — a leftover (e.g. a worktree whose base repo was lost, leaving a
  dangling `.git`). sync **repairs it without losing work**: if the base repo is
  still intact it just re-links the worktree in place (`git worktree repair`, no
  files moved); otherwise it **archives** the directory aside to
  `<dest>.broken-<utc>` (a `mv`, never a delete — your tracked, modified and
  untracked files are preserved there) and reprovisions a fresh checkout. the
  archive is left for you to inspect / recover from and is never auto-removed.

if aligning the remote fails outright (e.g. it still isn't a healthy codespace),
that repo's sync now **aborts with a clear error** instead of starting a watch
and reporting success — in a stack the repo is listed under `failed:` and the
others still sync.

### uncommitted changes

by default (`--mode dirty`, alias `-m d`) sync mirrors your uncommitted working
tree too, not just commits (gitignored paths don't count). a plain `codespace
sync` is a **one-shot**: it integrates commits, then overlays your working tree
onto the remote with a dependency-free `rsync` (honoring `.gitignore`, so heavy
dirs like `node_modules/` never travel). the overlay is only allowed when the
remote is clean, so it can't clobber independent remote work.

if the overlay would clobber **uncommitted work on the remote**, sync refuses;
interactively it offers:

```
[r]etry  [c]ommits-only  [a]bort
```

- **commits-only** (`--mode commits`, `-m c`) — sync just the commit history and
  leave the uncommitted tree untouched (local-only). to turn dirty work into
  history, `git commit` it yourself, then sync.
- non-interactive runs (agents/CI) don't prompt — reconcile the remote or pass
  `--mode commits`.

for *continuous* uncommitted mirroring rather than a single overlay, use
`--watch` (see below) — that's the only mode that keeps a live session running.

> note: a one-shot overlay leaves the remote with uncommitted changes, so the
> next plain `codespace sync` will see the remote as dirty. commit, or overlay
> again. a live `--watch` session (below) avoids this.

`--dry-run` prints the plan and mutates nothing.

### live sync (`--watch`)

`--watch` is the single, explicit continuous-sync mechanism. nothing is
"sticky" — a plain `codespace sync` is always a clean one-shot, and only
`--watch` keeps running. it works in **both** modes.

```sh
codespace sync --watch         # foreground: mirror continuously until Ctrl-C
codespace sync --watch -d       # --detach: run in the background, return now
codespace sync --stop           # tear the watch down (alias: --stop-watch)
```

in the default **dirty** mode it keeps a persistent, bidirectional file sync
running so both trees converge as you type — committed *and* uncommitted, no
divergence until you commit:

- it's backed by [mutagen](https://mutagen.io) — an **optional** dependency we
  only fetch when you opt in. on first use we check both ends and offer to
  install it locally and on the remote; decline and (interactively) it falls
  back to a one-shot overlay.
- gitignored paths (and `.git`, `open`, `.codespace/`) are excluded, so heavy
  dirs like `node_modules/` never sync.
- in the **foreground** it streams live status notices and tears down on Ctrl-C
  (terminating the session, clearing the marker). `--detach` (`-d`) instead
  spawns a background poller — its pid is recorded in the `.codespace/sync`
  marker — and returns immediately; `--stop` later kills that process and the
  session.

**commits ride a `HEAD` poll, not the file session.** mutagen mirrors the
working tree only, and a commit doesn't change file contents on disk, so commits
never travel through the live session. instead the watch process polls `HEAD`
and, on a change, integrates the new commits as history (both ways), freezing
the live session around the git ops. committing during a live session is
therefore safe, **including partial commits**: the non-committing side's
remainder is stashed, the committed subset integrates, the remainder is
restored, the session resumes — nothing uncommitted is lost. concurrent syncs
are serialized by a per-codespace lock. (there are **no git hooks**; the watch
process owns commit propagation for as long as it runs, and leaves nothing
behind on either end once stopped.)

> upgrading from an older version? earlier releases drove commit sync with a
> `post-commit` hook installed on both ends. the first `codespace sync` after
> upgrading detects and removes those automatically (restoring any hook they had
> shadowed) — no manual cleanup needed.

- genuine two-way edit conflicts are surfaced and you're prompted to resolve
  them manually or via a *commit-both-ends* bridge (commit each side, then
  reconcile as a normal rebase conflict).

**watching commits only** — `--watch` also works under `--mode=commits`, where
it skips the live file session entirely and just polls `HEAD`: every new commit
auto-syncs (commits only; your dirty tree stays local), needs no mutagen, and
tears down on `--stop`. `-d`/`--detach` runs it in the background. reach for it
when you want commit-level mirroring as you work but don't want uncommitted
files leaving your machine.

```sh
codespace sync --watch --mode=commits        # auto-sync each new commit
codespace sync --watch --mode=commits -d      # ... in the background
```

> a new `codespace sync` (or `--watch`) is **refused** while a watch is already
> running for that codespace — `--stop` it first. `--stop` itself is always
> allowed.

### opening the remote directly

`codespace open -r [host]` (or `edit -r`) opens a *local* codespace's **remote**
counterpart: it provisions + integrates the remote, starts a **detached**
`--watch` so your edits keep flowing, then opens over ssh-remote. host resolves
from the `.codespace/sync` marker if omitted. if a watch is already running it
just opens (it won't start a second one). this is the one-command "send me to
the big machine, keep my edits flowing" path; `codespace sync --stop` when
you're done.

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
