#!/usr/bin/env bats

# Phase 3 live (mutagen) sync for `codespace sync`, against the local-remote
# harness with a fake `mutagen` on PATH: session lifecycle, idempotency,
# sticky --watch, the no-mutagen fallback, and --stop-watch teardown.

load helpers

DEST="codespace/projects/myrepo_feat"

setup() {
	common_setup
	setup_local_remote
	export CS_NO_EDIT=1

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

_session() { echo "codespace-projects-myrepo-feat"; }
_hook() { echo "$(git -C "$CS" rev-parse --git-path hooks)/post-commit"; }

@test "watch: --watch starts a two-way-safe session with ignores; marker live; idempotent" {
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
	[ -f "$(_hook)" ]

	# re-watch is idempotent: no second `sync create`.
	run codespace sync --watch
	assert_success
	run grep -c 'sync create' "$MUTAGEN_LOG"
	assert_output "1"
}

@test "watch: -w is an alias for --watch" {
	install_mutagen_shim
	run codespace sync -r user@h -w
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=live"
}

@test "watch: without mutagen, --watch on a clean tree engages anyway, then syncs commits" {
	run codespace sync -r user@h --watch
	assert_success
	# --watch now always tries to engage the live session, so it surfaces the
	# missing mutagen (instead of silently syncing commits) before degrading.
	# (the install hint mentions --once, but a clean tree must NOT actually
	# perform an overlay — it degrades straight to commit-only.)
	assert_output --partial "mutagen"
	refute_output --partial "falling back to a one-shot overlay"

	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=commit"
	[ ! -f "$(_hook)" ]
}

@test "watch: --detach starts the session and returns without monitoring" {
	install_mutagen_shim
	force_interactive
	run codespace sync -r user@h -w -d
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]
	run grep -c 'sync monitor' "$MUTAGEN_LOG"
	assert_output "0"
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

@test "watch: -w with --mode=commits still engages a live session (mode coerced to all)" {
	install_mutagen_shim
	force_interactive
	# regression: combining --watch with a mode flag must NOT bail early -- it
	# stays active. --watch always mirrors uncommitted work, so mode -> all.
	run codespace sync -r user@h -w --mode=commits
	assert_success
	assert_output --partial "using --mode=all"
	[ -f "$MUTAGEN_STATE/$(_session)" ]
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=live"
}

@test "watch: without mutagen + uncommitted, --watch (non-interactive) falls back to overlay" {
	echo dirty >> file.txt

	run codespace sync -r user@h --watch
	assert_success
	assert_output --partial "one-shot overlay"

	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=overlay"
}

@test "watch: a later dirty sync auto-watches when mutagen is present (no flag)" {
	install_mutagen_shim
	run codespace sync -r user@h --watch
	assert_success

	echo dirty >> file.txt    # uncommitted; mutagen on both ends keeps mirroring
	run codespace sync
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=live"
}

@test "watch: --stop-watch terminates the session, removes the hook, clears the marker" {
	install_mutagen_shim
	run codespace sync -r user@h --watch
	assert_success
	[ -f "$MUTAGEN_STATE/$(_session)" ]
	[ -f "$(_hook)" ]

	run codespace sync --stop-watch
	assert_success
	[ ! -f "$MUTAGEN_STATE/$(_session)" ]
	[ ! -f "$(_hook)" ]
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
