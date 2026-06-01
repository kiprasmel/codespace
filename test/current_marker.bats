#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

# --- cs_mark_current: worktree ---------------------------------------------

@test "mark_current: writes marker with kind=worktree and fields" {
	mkrepo "$SANDBOX/work/myrepo"
	cd "$SANDBOX/work/myrepo"

	run --separate-stderr cs_mark_current "add dark mode"
	assert_success

	# path is the canonical repo root (git's --show-toplevel, realpath-resolved)
	local expect_root
	expect_root="$(git rev-parse --show-toplevel)"

	assert [ -f "$SANDBOX/work/myrepo/.codespace/current" ]
	assert_equal "$(cs_current_marker_get "$SANDBOX/work/myrepo" kind)" "worktree"
	assert_equal "$(cs_current_marker_get "$SANDBOX/work/myrepo" path)" "$expect_root"
	assert_equal "$(cs_current_marker_get "$SANDBOX/work/myrepo" branch)" "master"
	assert_equal "$(cs_current_marker_get "$SANDBOX/work/myrepo" task)" "add dark mode"
}

@test "mark_current: marker is git-excluded (won't trip rm safety / status)" {
	mkrepo "$SANDBOX/work/myrepo"
	cd "$SANDBOX/work/myrepo"
	cs_mark_current "x" >/dev/null 2>&1

	# excluded -> not shown as untracked in status
	run git status --porcelain
	refute_output --partial ".codespace"
	# exclude file records the marker
	run cat .git/info/exclude
	assert_output --partial ".codespace/current"
	# rm-safety's untracked listing must not include the marker
	run git ls-files --others --exclude-standard
	refute_output --partial ".codespace"
}

# --- cs_mark_current: stack -------------------------------------------------

@test "mark_current: stack dir -> kind=stack, no git needed" {
	mkdir -p "$SANDBOX/work/stack_feat"
	cd "$SANDBOX/work/stack_feat"

	run --separate-stderr cs_mark_current "stack task"
	assert_success

	assert_equal "$(cs_current_marker_get "$SANDBOX/work/stack_feat" kind)" "stack"
	assert_equal "$(cs_current_marker_get "$SANDBOX/work/stack_feat" branch)" "feat"
	assert_equal "$(cs_current_marker_get "$SANDBOX/work/stack_feat" path)" "$SANDBOX/work/stack_feat"
}

# --- cs_current_marker_find / cs_current ------------------------------------

@test "current_marker_find: walks up from a subdir" {
	mkrepo "$SANDBOX/work/myrepo"
	cd "$SANDBOX/work/myrepo"
	cs_mark_current "x" >/dev/null 2>&1
	mkdir -p sub/deep
	cd sub/deep

	run cs_current_marker_find
	assert_success
	assert_output "$SANDBOX/work/myrepo"
}

@test "current_marker_find: returns non-zero when no marker" {
	mkdir -p "$SANDBOX/empty"
	cd "$SANDBOX/empty"

	run cs_current_marker_find
	assert_failure
	refute_output
}

@test "current: prints whole marker or a single key" {
	mkrepo "$SANDBOX/work/myrepo"
	cd "$SANDBOX/work/myrepo"
	cs_mark_current "the task" >/dev/null 2>&1

	run cs_current kind
	assert_success
	assert_output "worktree"

	run cs_current
	assert_success
	assert_line "task=the task"
}

@test "current: no marker -> failure with hint" {
	mkdir -p "$SANDBOX/empty"
	cd "$SANDBOX/empty"

	run --separate-stderr cs_current
	assert_failure
	[[ "$stderr" == *"no .codespace/current marker"* ]]
}
