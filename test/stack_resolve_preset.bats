#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

# --- cs_stack_resolve_default_preset ----------------------------------------

@test "resolve_preset: anchor repo name matches preset key" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace", "codespace-stack"],
    "default": ["codespace"]
  }'
	mkrepo "$SANDBOX/projects/codespace"
	cd "$SANDBOX/projects/codespace"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "codespace"
	[[ "$stderr" == *"from repo context"* ]]
}

@test "resolve_preset: inside stack sub-repo uses fingerprint not anchor key" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "my-full-stack": ["codespace", "codespace-stack"]
  }'
	mkrepo "$SANDBOX/projects/codespace"
	mkdir -p "$SANDBOX/projects/stack_foo/codespace/.git" \
		"$SANDBOX/projects/stack_foo/codespace-stack/.git"
	git -C "$SANDBOX/projects/codespace" worktree add -b stack-branch \
		"$SANDBOX/projects/stack_foo/codespace" master 2>/dev/null || true
	cd "$SANDBOX/projects/stack_foo/codespace"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "my-full-stack"
	[[ "$stderr" == *"fingerprint"* ]]
}

@test "resolve_preset: satellite repo resolves via repo membership" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace", "codespace-stack"]
  }'
	mkrepo "$SANDBOX/projects/codespace-stack"
	cd "$SANDBOX/projects/codespace-stack"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "codespace"
	[[ "$stderr" == *"listed in preset"* ]]
}

@test "resolve_preset: defaults map when membership is ambiguous" {
	local cfg="$SANDBOX/projects/stacks.json"
	export STACKS_DEFAULTS_JSON='{ "codespace-stack": "codespace-full" }'
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace", "codespace-stack"],
    "codespace-full": ["codespace", "codespace-stack", "extra"]
  }'
	unset STACKS_DEFAULTS_JSON
	mkrepo "$SANDBOX/projects/codespace-stack"
	cd "$SANDBOX/projects/codespace-stack"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "codespace-full"
	[[ "$stderr" == *"defaults map"* ]]
}

@test "resolve_preset: fingerprint match at stack root" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace", "codespace-stack"],
    "default": ["codespace"]
  }'
	mkdir -p "$SANDBOX/projects/stack_foo/codespace/.git" \
		"$SANDBOX/projects/stack_foo/codespace-stack/.git"
	cd "$SANDBOX/projects/stack_foo"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "codespace"
	[[ "$stderr" == *"fingerprint"* ]]
}

@test "resolve_preset: ambiguous fingerprint tie falls through to default" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "fe": ["frontend", "backend"],
    "be": ["frontend", "backend"],
    "default": ["frontend"]
  }'
	mkdir -p "$SANDBOX/projects/stack_all/frontend/.git" "$SANDBOX/projects/stack_all/backend/.git"
	cd "$SANDBOX/projects/stack_all"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "default"
	[[ "$stderr" == *"org-wide fallback"* ]]
}

@test "resolve_preset: no fingerprint match falls through to default" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "fe": ["frontend"],
    "default": ["frontend", "backend", "infra"]
  }'
	mkdir -p "$SANDBOX/projects/stack_all/frontend/.git" "$SANDBOX/projects/stack_all/backend/.git"
	cd "$SANDBOX/projects/stack_all"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "default"
	[[ "$stderr" == *"org-wide fallback"* ]]
}

@test "resolve_preset: explicit -s bypasses inference" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace"],
    "fe": ["frontend"]
  }'
	mkrepo "$SANDBOX/projects/codespace"
	cd "$SANDBOX/projects/codespace"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" "fe"
	assert_success
	assert_output "fe"
	refute_output --partial "note:"
}

@test "resolve_preset: no match and no default preset errors" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace"]
  }'
	mkdir -p "$SANDBOX/work"
	cd "$SANDBOX/work"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_failure
	[[ "$stderr" == *"could not infer stack preset"* ]]
	[[ "$stderr" == *"available presets"* ]]
}
