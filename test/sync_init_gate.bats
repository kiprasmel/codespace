#!/usr/bin/env bats

# `codespace sync` provisioning gate: init is a tri-state, last-wins flag.
#   auto (default) -> provision only when the remote is absent/broken
#   force (--init)  -> re-run remote setup even on a healthy remote (idempotent)
#   no (--no-init)  -> code-only; error clearly if the remote isn't set up yet
# Exercised over the local-remote shim so the real provision path runs.

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
	git config user.email t@e.com
	git config user.name t
	echo hello > file.txt
	git add -A && git commit -q -m init
	git push -q origin master
	git branch feat
	git worktree add -q "$SANDBOX/projects/myrepo_feat" feat

	CS="$SANDBOX/projects/myrepo_feat"
	cd "$CS"
}

@test "gate: --no-init on an absent remote errors clearly and provisions nothing" {
	run codespace sync -r user@h --no-init
	assert_failure
	assert_output --partial "not provisioned"
	assert [ ! -e "$REMOTE_HOME/$DEST/.git" ]
}

@test "gate: --no-init defers, a later plain sync provisions (spin up later)" {
	echo change >> file.txt && git add -A && git commit -q -m c1

	run codespace sync -r user@h --no-init
	assert_failure
	assert [ ! -e "$REMOTE_HOME/$DEST/.git" ]

	run codespace sync -r user@h
	assert_success
	assert [ -e "$REMOTE_HOME/$DEST/.git" ]
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
}

@test "gate: auto skips setup on a healthy remote; --init forces a re-run" {
	run codespace sync -r user@h
	assert_success
	assert_output --partial "provisioning"

	# a routine re-sync leaves a healthy remote as-is (no setup re-run).
	run codespace sync
	assert_success
	refute_output --partial "re-running remote setup"

	# --init (== --init=force) re-runs setup even though it's already healthy.
	run codespace sync --init
	assert_success
	assert_output --partial "re-running remote setup"
}

@test "gate: --init is last-wins (dry-run reflects the final mode)" {
	run codespace sync -r user@h
	assert_success

	# --no-init then --init => force
	run codespace sync --dry-run --no-init --init
	assert_success
	assert_output --partial "would (re-)run remote setup"

	# --init then --no-init => no (healthy remote, so no error; code-only)
	run codespace sync --dry-run --init --no-init
	assert_success
	refute_output --partial "would (re-)run remote setup"
}

@test "gate: --no-init on a healthy remote syncs code only (no setup, no error)" {
	run codespace sync -r user@h
	assert_success

	echo change >> file.txt && git add -A && git commit -q -m c1
	run codespace sync --no-init
	assert_success
	refute_output --partial "re-running remote setup"
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
}
