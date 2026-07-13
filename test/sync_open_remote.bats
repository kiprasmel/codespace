#!/usr/bin/env bats

# Phase 3: `codespace open -r [host]` -- ensure the local codespace is synced
# (provision + integrate + start live sync), then open the remote counterpart.
# Editor open is a no-op under CS_NO_EDIT; we assert the sync side effects and
# that the marker host is honored on a subsequent `open -r` without a host.

load helpers

DEST="codespace/projects/myrepo_feat"

setup() {
	common_setup
	setup_local_remote
	install_mutagen_shim
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
	local pid
	pid="$(grep '^watch_pid=' "$CS/.codespace/sync" 2>/dev/null | cut -d= -f2)" || pid=""
	[ -n "$pid" ] && kill "$pid" 2>/dev/null || true
}

@test "open -r: provisions + syncs the remote, records the marker, prints the path" {
	run codespace open -r user@h
	assert_success
	assert_output --partial "$CS"

	[ -e "$REMOTE_HOME/$DEST/.git" ]
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	run grep '^host=' "$CS/.codespace/sync"
	assert_output "host=user@h"
	# -r implies wanting it live: a session is up
	[ -f "$MUTAGEN_STATE/codespace-projects-myrepo-feat" ]
}

@test "open -r: a later open -r (no host) reuses the marker's host" {
	run codespace open -r user@h
	assert_success

	echo more >> file.txt && git add -A && git commit -q -m more

	# a watch is already live, so a second open -r doesn't start (or block on) a
	# second sync -- it just opens. It must still resolve the host from the marker
	# rather than erroring for a missing -r value.
	run codespace open -r
	assert_success
	assert_output --partial "watch is already running"
	assert_output --partial "codespace sync --stop"
	run grep '^host=' "$CS/.codespace/sync"
	assert_output "host=user@h"

	# the live watch propagates the new commit on its next poll; drive one
	# integrate tick to prove it converges against the host from the marker.
	source_sync
	run cs_sync_watch_integrate "$CS" user@h
	assert_success
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
}
