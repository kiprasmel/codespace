#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

@test "post_create_config: returns default stack-post-create.sh path" {
	local cfg="$SANDBOX/stacks.json" config_dir="$SANDBOX"
	mk_stacks_json "$cfg"

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output "$config_dir/stack-post-create.sh"
}

@test "post_create_config: customPostCreateScript overrides default" {
	local cfg="$SANDBOX/stacks.json" config_dir="$SANDBOX"
	mk_stacks_json_ex "$cfg" '{
    "default": {
      "repos": ["repo-a"],
      "customPostCreateScript": "custom-post-create.sh"
    }
  }'

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output "$config_dir/custom-post-create.sh"
}

@test "post_create_config: ignores removed enableGlobalPostCreateScript flag" {
	local cfg="$SANDBOX/stacks.json" config_dir="$SANDBOX"
	cat > "$cfg" <<'EOF'
{
  "version": "0",
  "enableGlobalPostCreateScript": false,
  "stacks": { "default": ["repo-a"] }
}
EOF

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output "$config_dir/stack-post-create.sh"
}
