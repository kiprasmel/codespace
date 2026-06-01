#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

# --- cs_stack_search_config: pure walk-up (no prompts, no error output) -----

@test "search_config: hit at current dir (level 0)" {
	unset CODESPACE_CONFIG_ROOT
	mk_stacks_json "$SANDBOX/work/stacks.json"
	cd "$SANDBOX/work"

	run --separate-stderr cs_stack_search_config
	assert_success
	assert_line --index 0 "$SANDBOX/work/stacks.json"
	assert_line --index 1 "$SANDBOX/work"
	assert_line --index 2 "0"
}

@test "search_config: hit N levels up reports the level" {
	unset CODESPACE_CONFIG_ROOT
	mk_stacks_json "$SANDBOX/work/stacks.json"
	mkdir -p "$SANDBOX/work/dir1/dir2"
	cd "$SANDBOX/work/dir1/dir2"

	run --separate-stderr cs_stack_search_config
	assert_success
	assert_line --index 0 "$SANDBOX/work/stacks.json"
	assert_line --index 1 "$SANDBOX/work"
	assert_line --index 2 "2"
}

@test "search_config: miss -> non-zero, no stdout, no error block" {
	unset CODESPACE_CONFIG_ROOT
	mkdir -p "$SANDBOX/work/project"
	cd "$SANDBOX/work/project"

	run --separate-stderr cs_stack_search_config
	assert_failure
	refute_output
	# search is quiet: it must NOT print the find_config error block
	[[ "$stderr" != *"stacks.json not found"* ]]
}
