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
	run codespace open -r
	assert_success
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
}
