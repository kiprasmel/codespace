#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

# --- cs_stack_find_config: walk-up resolution -------------------------------

@test "find_config: config at current dir (level 0)" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	mkdir -p "$SANDBOX/work"
	cd "$SANDBOX/work"

	run --separate-stderr cs_stack_find_config
	assert_success
	assert_line --index 0 "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	assert_line --index 1 "$SANDBOX/work"
	# no "levels up" note at level 0 or 1
	refute_output --partial "levels up"
}

@test "find_config: config only at parent (level 1) - no prompt" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	mkdir -p "$SANDBOX/work/project"
	cd "$SANDBOX/work/project"

	run --separate-stderr cs_stack_find_config
	assert_success
	assert_line --index 0 "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	assert_line --index 1 "$SANDBOX/work"
	# level 1 should not trigger the prompt
	refute [ "${stderr:-}" = "*levels up*" ]
}

@test "find_config: config at grandparent (level 2+) triggers auto-accept" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	mkdir -p "$SANDBOX/work/dir1/dir2"
	cd "$SANDBOX/work/dir1/dir2"

	run --separate-stderr cs_stack_find_config
	assert_success
	assert_line --index 0 "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	assert_line --index 1 "$SANDBOX/work"
	[[ "$stderr" == *"levels up"* ]]
	[[ "$stderr" == *"auto-accepting"* ]]
}

@test "find_config: org-committed stacks.json works without CODESPACE_CONFIG_ROOT" {
	unset CODESPACE_CONFIG_ROOT
	mk_stacks_json "$SANDBOX/work/stacks.json"
	mkdir -p "$SANDBOX/work/project"
	cd "$SANDBOX/work/project"

	run --separate-stderr cs_stack_find_config
	assert_success
	assert_line --index 0 "$SANDBOX/work/stacks.json"
	assert_line --index 1 "$SANDBOX/work"
}

@test "find_config: org-committed .codespace/stacks.json preferred over bare" {
	unset CODESPACE_CONFIG_ROOT
	mk_stacks_json "$SANDBOX/work/stacks.json"
	mk_stacks_json "$SANDBOX/work/.codespace/stacks.json"
	cd "$SANDBOX/work"

	run --separate-stderr cs_stack_find_config
	assert_success
	assert_line --index 0 "$SANDBOX/work/.codespace/stacks.json"
	assert_line --index 1 "$SANDBOX/work"
}

@test "find_config: nothing anywhere -> non-zero with helpful hint" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$SANDBOX/work/project"
	cd "$SANDBOX/work/project"

	run --separate-stderr cs_stack_find_config
	assert_failure
	[[ "$stderr" == *"stacks.json not found"* ]]
	[[ "$stderr" == *".codespace/stacks.json"* ]]
	[[ "$stderr" == *"stack init"* ]]
}

@test "find_config: nothing, no CODESPACE_CONFIG_ROOT -> hint mentions skipped user search" {
	unset CODESPACE_CONFIG_ROOT
	mkdir -p "$SANDBOX/work/project"
	cd "$SANDBOX/work/project"

	run --separate-stderr cs_stack_find_config
	assert_failure
	[[ "$stderr" == *"user-level search skipped"* ]]
}
