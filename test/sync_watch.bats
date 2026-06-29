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

@test "watch: without mutagen, --watch on a clean tree syncs commits only (no overlay/prompt)" {
	run codespace sync -r user@h --watch
	assert_success
	refute_output --partial "one-shot overlay"
	refute_output --partial "mutagen"

	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=commit"
	[ ! -f "$(_hook)" ]
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

@test "watch: ensure_mutagen reports missing sides and (non-interactive) declines" {
	source_sync
	run cs_sync_ensure_mutagen user@h
	assert_failure
	assert_output --partial "missing on"
}
