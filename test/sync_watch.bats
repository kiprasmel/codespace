#!/usr/bin/env bats

# Live (mutagen) + commit-poll watch for `codespace sync`, against the
# local-remote harness with a fake `mutagen` on PATH: session lifecycle, the
# no-mutagen fallback, --detach (a PID-tracked background poller), --stop
# teardown, the watch-already-running guard, and the mutagen-free commits-mode
# watch. No post-commit hooks anywhere -- commits ride the poll loop.
#
# CS_WATCH_POLL_MAX=0 bounds every watch loop (foreground + the detached child)
# to zero iterations so tests never sleep or leak a forever-poller.

load helpers

DEST="codespace/projects/myrepo_feat"

setup() {
	common_setup
	setup_local_remote
	export CS_NO_EDIT=1
	export CS_WATCH_POLL_MAX=0

	git init -q --bare "$SANDBOX/origin.git"
	mkdir -p "$SANDBOX/projects"
	git clone -q "$SANDBOX/origin.git" "$SANDBOX/projects/myrepo" 2>/dev/null
	cd "$SANDBOX/projects/myrepo"
	git config user.email t@e.com && git config user.name t
	echo hello > file.txt
	git add -A && git commit -q -m init
	git push -q origin master
	git branch feat
	git worktree add -q "$SANDBOX/projects/myrepo_feat" feat

	CS="$SANDBOX/projects/myrepo_feat"
	cd "$CS"
}

teardown() {
	# kill any detached poller a test left behind (defensive; most exit at once).
	local pid
	pid="$(grep '^watch_pid=' "$CS/.codespace/sync" 2>/dev/null | cut -d= -f2)" || pid=""
	[ -n "$pid" ] && kill "$pid" 2>/dev/null || true
}

_session() { echo "codespace-projects-myrepo-feat"; }
_hook() { echo "$(git -C "$CS" rev-parse --git-path hooks)/post-commit"; }
_marker_pid() { grep '^watch_pid=' "$CS/.codespace/sync" 2>/dev/null | cut -d= -f2; }

@test "watch: --watch starts a two-way-safe session with ignores; marker live; no hook" {
	install_mutagen_shim
	printf 'node_modules/\n' > .gitignore && git add -A && git commit -q -m gitignore

	run codespace sync -r user@h --watch
	assert_success

	[ -f "$MUTAGEN_STATE/$(_session)" ]
	run grep 'sync create' "$MUTAGEN_LOG"
	assert_output --partial "sync-mode=two-way-safe"
	assert_output --partial "ignore-vcs"
	assert_output --partial "ignore=node_modules/"
	# the remote endpoint must be mutagen's scp-style host:path (home-relative),
	# NOT a ssh:// URL (which mutagen misparses, dialing host "ssh").
	assert_output --partial "user@h:$DEST"
	refute_output --partial "ssh://"

	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=live"
	run grep '^mutagen_session=' "$CS/.codespace/sync"
	assert_output "mutagen_session=$(_session)"
	# commits ride the poll loop now -- no post-commit hook is ever installed.
	[ ! -f "$(_hook)" ]
}

@test "watch: -w is an alias for --watch" {
	install_mutagen_shim
	run codespace sync -r user@h -w
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=live"
}

@test "watch: a second sync/watch is refused while a watch is live (--stop first)" {
	install_mutagen_shim
	run codespace sync -r user@h -w
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]

	# a live session counts as a running watch: refuse a new watch ...
	run codespace sync -w
	assert_failure
	assert_output --partial "already running"
	assert_output --partial "--stop"

	# ... and a plain one-shot sync too (don't race the same tree).
	run codespace sync
	assert_failure
	assert_output --partial "already running"

	# only one `sync create` ever happened.
	run grep -c 'sync create' "$MUTAGEN_LOG"
	assert_output "1"
}

@test "watch: without mutagen, --watch on a clean tree engages anyway, degrades to commit-only" {
	run codespace sync -r user@h --watch
	assert_success
	# --watch always tries to engage the live session, surfacing the missing
	# mutagen (instead of silently syncing commits) before degrading. (a clean
	# tree must NOT overlay -- it degrades straight to commit-only.)
	assert_output --partial "mutagen"
	refute_output --partial "falling back to a one-shot overlay"

	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=commit"
	[ ! -f "$(_hook)" ]
}

@test "watch: --detach starts the session, records a watch pid, and returns without monitoring" {
	install_mutagen_shim
	force_interactive
	run codespace sync -r user@h -w -d
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]
	# detached: never hands the terminal to `sync monitor`.
	run grep -c 'sync monitor' "$MUTAGEN_LOG"
	assert_output "0"
	# a background poller pid was recorded.
	run grep -c '^watch_pid=' "$CS/.codespace/sync"
	assert_output "1"
}

@test "watch: foreground --watch monitors the live session (interactive)" {
	install_mutagen_shim
	force_interactive
	run codespace sync -r user@h -w
	assert_success
	# the foreground renderer streams a templated `sync monitor` over the session.
	run grep 'sync monitor' "$MUTAGEN_LOG"
	assert_output --partial "sync monitor"
	assert_output --partial "$(_session)"
	# not interrupted (no Ctrl-C), so the session stays alive.
	[ -f "$MUTAGEN_STATE/$(_session)" ]
}

@test "watch: -w --mode=commits polls commits with no session, no mutagen, no hook" {
	install_mutagen_shim
	force_interactive
	# commits-mode watch: no live session, dirty tree left local; new commits are
	# carried by the HEAD poll loop (bounded to 0 iterations here).
	run codespace sync -r user@h -w --mode=commits
	assert_success
	assert_output --partial "watching"
	# no live session was created, even with mutagen available.
	[ ! -f "$MUTAGEN_STATE/$(_session)" ]
	run grep -c 'sync create' "$MUTAGEN_LOG"
	assert_output "0"
	# no hook anywhere.
	[ ! -f "$(_hook)" ]
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=commit"
}

@test "watch: -w --mode=commits -d returns immediately, needs no mutagen, records a pid" {
	force_interactive
	run codespace sync -r user@h -w --mode=commits -d
	assert_success
	refute_output --partial "Ctrl-C"
	run grep -c '^watch_pid=' "$CS/.codespace/sync"
	assert_output "1"
	[ ! -f "$(_hook)" ]
}

@test "watch: --stop clears a detached commits-mode watch" {
	force_interactive
	run codespace sync -r user@h -w --mode=commits -d
	assert_success
	run grep -c '^watch_pid=' "$CS/.codespace/sync"
	assert_output "1"

	run codespace sync --stop
	assert_success
	run grep -c '^watch_pid=' "$CS/.codespace/sync"
	assert_output "0"
}

@test "watch: --stop kills a live background watch process" {
	force_interactive
	# a long interval keeps the spawned poller alive (sleeping) so we can prove
	# --stop actually kills the process, not just clears the marker.
	run env CS_WATCH_POLL_MAX=1000 CS_WATCH_POLL_INTERVAL=120 \
		codespace sync -r user@h -w --mode=commits -d
	assert_success
	local pid; pid="$(_marker_pid)"
	[ -n "$pid" ]
	kill -0 "$pid" 2>/dev/null            # alive

	run codespace sync --stop
	assert_success
	! kill -0 "$pid" 2>/dev/null          # dead
	run grep -c '^watch_pid=' "$CS/.codespace/sync"
	assert_output "0"
}

@test "watch: without mutagen + uncommitted, --watch (non-interactive) falls back to overlay" {
	echo dirty >> file.txt

	run codespace sync -r user@h --watch
	assert_success
	assert_output --partial "one-shot overlay"

	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=overlay"
}

@test "watch: no stickiness -- a plain dirty sync after --stop overlays once (not live)" {
	install_mutagen_shim
	run codespace sync -r user@h -w
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]

	run codespace sync --stop
	assert_success
	[ ! -f "$MUTAGEN_STATE/$(_session)" ]

	# a later dirty sync (mutagen present) is a ONE-SHOT overlay, not a re-engaged
	# live session -- only --watch starts a session.
	echo dirty >> file.txt
	run codespace sync
	assert_success
	[ ! -f "$MUTAGEN_STATE/$(_session)" ]
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=overlay"
}

@test "watch: --stop-watch terminates the session and clears the marker" {
	install_mutagen_shim
	run codespace sync -r user@h --watch
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]

	run codespace sync --stop-watch
	assert_success
	[ ! -f "$MUTAGEN_STATE/$(_session)" ]
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=commit"
	run grep -c '^mutagen_session=' "$CS/.codespace/sync"
	assert_output "0"
}

@test "watch: --stop is an alias for --stop-watch" {
	install_mutagen_shim
	run codespace sync -r user@h --watch
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]

	run codespace sync --stop
	assert_success
	[ ! -f "$MUTAGEN_STATE/$(_session)" ]
}

@test "watch: ensure_mutagen reports missing sides and (non-interactive) declines" {
	source_sync
	run cs_sync_ensure_mutagen user@h
	assert_failure
	assert_output --partial "missing on"
}
