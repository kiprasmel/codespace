#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

# --- cs_stack_find_in_dir ---------------------------------------------------

@test "find_in_dir: prefers .codespace/stacks.json over bare" {
	mkdir -p "$SANDBOX/work/.codespace"
	mk_stacks_json "$SANDBOX/work/stacks.json"
	mk_stacks_json "$SANDBOX/work/.codespace/stacks.json"

	run cs_stack_find_in_dir "$SANDBOX/work"
	assert_success
	assert_output "$SANDBOX/work/.codespace/stacks.json"
}

@test "find_in_dir: falls back to bare stacks.json" {
	mk_stacks_json "$SANDBOX/work/stacks.json"

	run cs_stack_find_in_dir "$SANDBOX/work"
	assert_success
	assert_output "$SANDBOX/work/stacks.json"
}

@test "find_in_dir: neither present returns non-zero, no output" {
	mkdir -p "$SANDBOX/work"

	run cs_stack_find_in_dir "$SANDBOX/work"
	assert_failure
	assert_output ""
}

# --- cs_stack_resolve_config_at ---------------------------------------------

@test "resolve_at: only org-committed (no CODESPACE_CONFIG_ROOT) -> org wins" {
	mk_stacks_json "$SANDBOX/work/stacks.json"

	run --separate-stderr cs_stack_resolve_config_at "$SANDBOX/work"
	assert_success
	assert_output "$SANDBOX/work/stacks.json"
	assert [ "$stderr" = "note: using stacks.json: $SANDBOX/work/stacks.json" ]
}

@test "resolve_at: only user-level -> user wins, no 'ignoring' note" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	mkdir -p "$SANDBOX/work"

	run --separate-stderr cs_stack_resolve_config_at "$SANDBOX/work"
	assert_success
	assert_output "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	assert [ "$stderr" = "note: using stacks.json: $CODESPACE_CONFIG_ROOT/work/stacks.json" ]
}

@test "resolve_at: both user-level and org-committed -> user wins, notes both" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	mk_stacks_json "$SANDBOX/work/stacks.json"

	run --separate-stderr cs_stack_resolve_config_at "$SANDBOX/work"
	assert_success
	assert_output "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	[[ "$stderr" == *"note: using stacks.json: $CODESPACE_CONFIG_ROOT/work/stacks.json"* ]]
	[[ "$stderr" == *"note: ignoring org-committed stacks.json: $SANDBOX/work/stacks.json"* ]]
}

@test "resolve_at: user .codespace/stacks.json beats user bare stacks.json" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/.codespace/stacks.json"
	mkdir -p "$SANDBOX/work"

	run --separate-stderr cs_stack_resolve_config_at "$SANDBOX/work"
	assert_success
	assert_output "$CODESPACE_CONFIG_ROOT/work/.codespace/stacks.json"
}

@test "resolve_at: user .codespace/stacks.json beats org .codespace/stacks.json" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/.codespace/stacks.json"
	mk_stacks_json "$SANDBOX/work/.codespace/stacks.json"

	run --separate-stderr cs_stack_resolve_config_at "$SANDBOX/work"
	assert_success
	assert_output "$CODESPACE_CONFIG_ROOT/work/.codespace/stacks.json"
	[[ "$stderr" == *"note: ignoring org-committed stacks.json: $SANDBOX/work/.codespace/stacks.json"* ]]
}

@test "resolve_at: org .codespace/stacks.json beats org bare stacks.json" {
	mk_stacks_json "$SANDBOX/work/stacks.json"
	mk_stacks_json "$SANDBOX/work/.codespace/stacks.json"

	run --separate-stderr cs_stack_resolve_config_at "$SANDBOX/work"
	assert_success
	assert_output "$SANDBOX/work/.codespace/stacks.json"
}

@test "resolve_at: neither present -> non-zero, no stdout" {
	mkdir -p "$SANDBOX/work"

	run --separate-stderr cs_stack_resolve_config_at "$SANDBOX/work"
	assert_failure
	assert_output ""
}
