#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

@test "post_create_config: returns default stack-post-create.sh when present" {
	local cfg="$SANDBOX/stacks.json" config_dir="$SANDBOX"
	mk_stacks_json "$cfg"
	echo '#!/usr/bin/env bash' > "$config_dir/stack-post-create.sh"
	chmod +x "$config_dir/stack-post-create.sh"

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output "$config_dir/stack-post-create.sh"
}

@test "post_create_config: empty when default script missing" {
	local cfg="$SANDBOX/stacks.json"
	mk_stacks_json "$cfg"

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output ""
}

@test "post_create_config: customPostCreateScript overrides default" {
	local cfg="$SANDBOX/stacks.json" config_dir="$SANDBOX"
	mk_stacks_json_ex "$cfg" '{
    "default": {
      "repos": ["repo-a"],
      "customPostCreateScript": "custom-post-create.sh"
    }
  }'
	echo '#!/usr/bin/env bash' > "$config_dir/custom-post-create.sh"
	chmod +x "$config_dir/custom-post-create.sh"

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output "$config_dir/custom-post-create.sh"
}

@test "post_create_config: empty when script not executable" {
	local cfg="$SANDBOX/stacks.json" config_dir="$SANDBOX"
	mk_stacks_json "$cfg"
	echo '#!/usr/bin/env bash' > "$config_dir/stack-post-create.sh"
	chmod -x "$config_dir/stack-post-create.sh"

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output ""
}

@test "post_create_config: ignores removed enableGlobalPostCreateScript flag" {
	local cfg="$SANDBOX/stacks.json"
	cat > "$cfg" <<'EOF'
{
  "version": "0",
  "enableGlobalPostCreateScript": false,
  "stacks": { "default": ["repo-a"] }
}
EOF

	run cs_stack_get_post_create_config "default" "$cfg"
	assert_success
	assert_output ""
}

@test "run_remote_stack_post_create: no-op when script missing on remote" {
	source_stack
	setup_local_remote

	run cs_stack_run_remote_stack_post_create user@host default feat stack_rel projects/myorg repo-a worktree stack-post-create.sh
	assert_success
	assert [ ! -f "$REMOTE_HOME/codespace-config/projects/myorg/stack-post-create.sh" ]
}
