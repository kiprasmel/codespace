#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
	export CODESPACE_CONFIG_ROOT="$SANDBOX/cfg"
}

@test "stack init: template has mixedProjects false, no enableGlobalPostCreateScript" {
	mkdir -p "$SANDBOX/projects"
	mkrepo "$SANDBOX/projects/repo-a"

	run --separate-stderr cs_stack_init "$SANDBOX/projects"
	assert_success

	local cfg="$CODESPACE_CONFIG_ROOT/projects/stacks.json"
	assert [ -f "$cfg" ]
	run jq -e '.mixedProjects == false' "$cfg"
	assert_success
	run jq -e '.enableGlobalPostCreateScript == null' "$cfg"
	assert_success
}
