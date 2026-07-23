#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack
}

teardown() {
	common_teardown
}

# --- cs_stack_resolve_default_preset ----------------------------------------

@test "resolve_preset: anchor repo name matches preset key (silent)" {
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
	[[ -z "${stderr:-}" ]]
}

@test "resolve_preset: codespace-cloud skips catch-all all preset" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace", "codespace-cloud"],
    "all": ["codespace", "codespace-cloud", "other"]
  }'
	mkrepo "$SANDBOX/projects/codespace-cloud"
	cd "$SANDBOX/projects/codespace-cloud"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "codespace"
	[[ -z "${stderr:-}" ]]
}

@test "resolve_preset: repo only in catch-all all preset" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace"],
    "all": ["codespace-cloud", "other"]
  }'
	mkrepo "$SANDBOX/projects/codespace-cloud"
	cd "$SANDBOX/projects/codespace-cloud"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "all"
	[[ -z "${stderr:-}" ]]
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
	[[ -z "${stderr:-}" ]]
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
	[[ -z "${stderr:-}" ]]
}

@test "resolve_preset: defaults map when membership is ambiguous" {
	local cfg="$SANDBOX/projects/stacks.json"
	export STACKS_DEFAULTS_JSON='{ "frontend": "fe-stack" }'
	mk_stacks_json_ex "$cfg" '{
    "fe": ["frontend", "backend"],
    "be": ["frontend", "backend"]
  }'
	unset STACKS_DEFAULTS_JSON
	mkrepo "$SANDBOX/projects/frontend"
	cd "$SANDBOX/projects/frontend"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "fe-stack"
	[[ -z "${stderr:-}" ]]
}

@test "resolve_preset: ambiguous membership errors with specific message" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "fe": ["frontend", "backend"],
    "be": ["frontend", "backend"]
  }'
	mkrepo "$SANDBOX/projects/frontend"
	cd "$SANDBOX/projects/frontend"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_failure
	[[ "$stderr" == *"matches multiple stack configs"* ]]
	[[ "$stderr" == *"fe"* ]]
	[[ "$stderr" == *"be"* ]]
	[[ "$stderr" == *"pass -s"* ]]
}

@test "resolve_preset: interactive pick via CS_STACK_PRESET_CHOICE" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "fe": ["frontend", "backend"],
    "be": ["frontend", "backend"]
  }'
	mkrepo "$SANDBOX/projects/frontend"
	cd "$SANDBOX/projects/frontend"
	force_interactive
	export CS_STACK_PRESET_CHOICE=1

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	unset CS_STACK_PRESET_CHOICE
	assert_success
	assert_output "be"
	[[ "$stderr" == *"select stack config"* ]]
}

@test "resolve_preset: fingerprint match at stack root (silent)" {
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
	[[ -z "${stderr:-}" ]]
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
	[[ -z "${stderr:-}" ]]
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
	[[ -z "${stderr:-}" ]]
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
	[[ -z "${stderr:-}" ]]
}

@test "resolve_preset: repo not in any preset prompts or errors" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace"]
  }'
	mkrepo "$SANDBOX/projects/orphan"
	cd "$SANDBOX/projects/orphan"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_failure
	[[ "$stderr" == *"not in any stack preset"* ]]
	[[ "$stderr" == *"pass -s"* ]]
}
