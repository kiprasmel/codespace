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

@test "resolve_preset: inside stack sub-repo uses anchor convention" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace", "codespace-stack"]
  }'
	mkrepo "$SANDBOX/projects/codespace"
	mkdir -p "$SANDBOX/projects/stack_foo"
	git -C "$SANDBOX/projects/codespace" worktree add -b stack-branch "$SANDBOX/projects/stack_foo/codespace" master
	cd "$SANDBOX/projects/stack_foo/codespace"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "codespace"
}

@test "resolve_preset: defaults map when preset key differs from anchor" {
	local cfg="$SANDBOX/projects/stacks.json"
	export STACKS_DEFAULTS_JSON='{ "codespace-stack": "codespace-full" }'
	mk_stacks_json_ex "$cfg" '{
    "codespace-full": ["codespace", "codespace-stack"]
  }'
	unset STACKS_DEFAULTS_JSON
	mkrepo "$SANDBOX/projects/codespace-stack"
	cd "$SANDBOX/projects/codespace-stack"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "codespace-full"
	[[ "$stderr" == *"defaults map"* ]]
}

@test "resolve_preset: stack marker wins over anchor convention" {
	local cfg="$SANDBOX/projects/stacks.json"
	mk_stacks_json_ex "$cfg" '{
    "codespace": ["codespace", "codespace-stack"],
    "other": ["other-app"]
  }'
	mkdir -p "$SANDBOX/projects/stack_foo"
	cs_stack_marker_write "$SANDBOX/projects/stack_foo" "other"
	cd "$SANDBOX/projects/stack_foo"

	run --separate-stderr cs_stack_resolve_default_preset "$cfg" ""
	assert_success
	assert_output "other"
	[[ "$stderr" == *"stack marker"* ]]
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

@test "resolve_preset: marker write and read roundtrip" {
	mkdir -p "$SANDBOX/stack_foo"
	cs_stack_marker_write "$SANDBOX/stack_foo" "codespace"
	run cs_stack_marker_get "$SANDBOX/stack_foo" "preset"
	assert_success
	assert_output "codespace"
}
