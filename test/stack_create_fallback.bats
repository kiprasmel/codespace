#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

# --- cs_stack_create: graceful fallback when no stacks.json -----------------

@test "stack create: no stacks.json -> falls back to single worktree" {
	unset CODESPACE_CONFIG_ROOT
	mkrepo "$SANDBOX/work/myrepo"
	cd "$SANDBOX/work/myrepo"

	run --separate-stderr cs_stack_create my-feature
	assert_success
	[[ "$stderr" == *"no stacks.json detected"* ]]

	# a single worktree was created on the branch...
	assert [ -d "$SANDBOX/work/myrepo_my-feature" ]
	assert_equal "$(git -C "$SANDBOX/work/myrepo_my-feature" branch --show-current)" "my-feature"
	# ...and NOT a stack
	refute [ -d "$SANDBOX/work/stack_my-feature" ]
}

@test "stack create: fallback notes that an explicit -s is ignored" {
	unset CODESPACE_CONFIG_ROOT
	mkrepo "$SANDBOX/work/myrepo"
	cd "$SANDBOX/work/myrepo"

	run --separate-stderr cs_stack_create -s full my-feature
	assert_success
	[[ "$stderr" == *"ignoring -s full"* ]]
	assert [ -d "$SANDBOX/work/myrepo_my-feature" ]
}
