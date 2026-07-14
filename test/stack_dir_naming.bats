#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils
	source_stack
}

# --- cs_stack_format_dir_basename / cs_stack_branch_from_dir_basename --------

@test "stack_dir_naming: legacy basename when mixedProjects off" {
	local cfg="$SANDBOX/stacks.json"
	mk_stacks_json "$cfg"

	run cs_stack_format_dir_basename "codespace" "feature-x" "$cfg"
	assert_success
	assert_output "stack_feature-x"
}

@test "stack_dir_naming: prefixed basename when mixedProjects on" {
	local cfg="$SANDBOX/stacks.json"
	mk_stacks_json_ex "$cfg" '{ "codespace": ["codespace"] }'
	jq '. + {"mixedProjects": true}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"

	run cs_stack_format_dir_basename "codespace" "feature-x" "$cfg"
	assert_success
	assert_output "stack_codespace_feature-x"
}

@test "stack_dir_naming: parse prefixed dir to branch" {
	local cfg="$SANDBOX/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace"],
    "codespace_cloud": ["codespace-cloud"]
  }'
	jq '. + {"mixedProjects": true}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"

	run cs_stack_branch_from_dir_basename "stack_codespace_cloud_feature-x" "$cfg"
	assert_success
	assert_output "feature-x"
}

@test "stack_dir_naming: legacy dir parses as full rest when mixedProjects on" {
	local cfg="$SANDBOX/stacks.json"
	mk_stacks_json_ex "$cfg" '{ "codespace": ["codespace"] }'
	jq '. + {"mixedProjects": true}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"

	run cs_stack_branch_from_dir_basename "stack_feature-x" "$cfg"
	assert_success
	assert_output "feature-x"
}

@test "stack_dir_naming: mixedProjects defaults false when absent" {
	local cfg="$SANDBOX/stacks.json"
	mk_stacks_json "$cfg"

	run cs_stack_mixed_projects_enabled "$cfg"
	assert_failure
}

@test "stack_dir_naming: create_setup_dirs uses prefixed path" {
	local org cfg
	org="$SANDBOX/projects"
	cfg="$org/stacks.json"
	mkdir -p "$org"
	mk_stacks_json_ex "$cfg" '{ "codespace": ["codespace"] }'
	jq '. + {"mixedProjects": true}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"

	export branch="feature-x"
	export stack_name="codespace"
	export org_dir="$org"
	export stacks_json="$cfg"
	export remote_host=""

	run cs_stack_create_setup_dirs
	assert_success
	assert [ -d "$org/stack_codespace_feature-x" ]
}

@test "stack_dir_naming: detect_current recovers branch from prefixed dir" {
	local org cfg
	org="$SANDBOX/projects"
	cfg="$org/stacks.json"
	mkdir -p "$org/stack_codespace_feature-x/codespace/.git"
	mk_stacks_json_ex "$cfg" '{ "codespace": ["codespace"] }'
	jq '. + {"mixedProjects": true}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
	cd "$org/stack_codespace_feature-x/codespace"

	run cs_stack_detect_current
	assert_success
	assert_line --index 0 "$org/stack_codespace_feature-x"
	assert_line --index 1 "feature-x"
	assert_line --index 2 "$org"
}
