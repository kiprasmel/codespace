#!/usr/bin/env bats

# cs_checkout_health classifies a git checkout on disk (pure; no ssh). It's the
# single source of truth cs_sync_remote_health ships to the remote verbatim, so
# cover its ok / absent / broken rules directly against real fixtures.

load helpers

setup() {
	common_setup
	source_utils
}

@test "checkout_health: absent when nothing at dest" {
	run cs_checkout_health "$SANDBOX/nope" "$SANDBOX/base" worktree
	assert_success
	assert_output absent
}

@test "checkout_health: ok for a clone (base irrelevant)" {
	mkrepo "$SANDBOX/clone"
	run cs_checkout_health "$SANDBOX/clone" "$SANDBOX/clone" clone
	assert_success
	assert_output ok
}

@test "checkout_health: ok for a worktree backed by a valid base repo" {
	mkrepo "$SANDBOX/base"
	git -C "$SANDBOX/base" worktree add -q -b feat "$SANDBOX/wt" >/dev/null
	run cs_checkout_health "$SANDBOX/wt" "$SANDBOX/base" worktree
	assert_success
	assert_output ok
}

@test "checkout_health: broken when the worktree's base repo is gone" {
	mkrepo "$SANDBOX/base"
	git -C "$SANDBOX/base" worktree add -q -b feat "$SANDBOX/wt" >/dev/null
	rm -rf "$SANDBOX/base"                       # dangling: .git points nowhere
	run cs_checkout_health "$SANDBOX/wt" "$SANDBOX/base" worktree
	assert_success
	assert_output broken
}

@test "checkout_health: broken when dest exists but isn't a checkout" {
	mkdir -p "$SANDBOX/junk"
	printf 'gitdir: /nonexistent\n' > "$SANDBOX/junk/.git"
	run cs_checkout_health "$SANDBOX/junk" "$SANDBOX/base" worktree
	assert_success
	assert_output broken
}
