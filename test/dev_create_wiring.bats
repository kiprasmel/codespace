#!/usr/bin/env bats

# `--dev` on create + the `dev` dispatch route:
#   - `codespace dev -h` is routed and prints usage (no side effects).
#   - stack `create --dev` runs `cs_dev` only for a REMOTE stack, AFTER the
#     provision completes, and is a graceful no-op locally.
#   - worktree `create --dev` parses the flag and forwards to `cs_dev`.

load helpers

setup() {
	common_setup
	install_ssh_shims
}

# --- dispatch route ---------------------------------------------------------

@test "dispatch: 'codespace dev -h' prints usage and exits 0" {
	run "$REPO_ROOT/codespace" dev -h
	assert_success
	assert_output --partial "codespace dev"
	assert_output --partial "--stop"
	assert_output --partial "--plain-ports"
}

# --- stack create --dev wiring ---------------------------------------------

@test "stack create: --dev is parsed into stack_run_dev" {
	source_stack
	# drive just the arg parser; it sets the stack_run_dev global.
	stack_run_dev=""
	cs_stack_create_parse_args feat --dev -r white-monster
	assert_equal "$stack_run_dev" "1"
}

@test "stack create_maybe_dev: no-op (no cs_dev) for a LOCAL stack" {
	source_stack
	cs_dev() { echo "CS_DEV_CALLED:$*"; }
	stack_run_dev=1
	remote_host=""
	stack_dir="$BATS_TEST_TMPDIR/stack_x"
	run cs_stack_create_maybe_dev
	assert_success
	refute_output --partial "CS_DEV_CALLED"
	assert_output --partial "no-op for a local stack"
}

@test "stack create_maybe_dev: REMOTE stack invokes cs_dev with the stack dir" {
	source_stack
	cs_dev() { echo "CS_DEV_CALLED:$*"; }
	stack_run_dev=1
	remote_host="white-monster"
	stack_dir="$BATS_TEST_TMPDIR/stack_x"
	run cs_stack_create_maybe_dev
	assert_success
	assert_output --partial "CS_DEV_CALLED:$BATS_TEST_TMPDIR/stack_x"
}

@test "stack create_maybe_dev: disabled unless --dev was given" {
	source_stack
	cs_dev() { echo "CS_DEV_CALLED"; }
	stack_run_dev=""
	remote_host="white-monster"
	stack_dir="$BATS_TEST_TMPDIR/stack_x"
	run cs_stack_create_maybe_dev
	assert_success
	refute_output --partial "CS_DEV_CALLED"
}

@test "stack create: dev runs AFTER provisioning (maybe_dev is the last step)" {
	source_stack
	body="$(declare -f cs_stack_create)"
	summarize_line="$(printf '%s\n' "$body" | grep -n 'cs_stack_create_wait_and_summarize' | head -n1 | cut -d: -f1)"
	dev_line="$(printf '%s\n' "$body" | grep -n 'cs_stack_create_maybe_dev' | head -n1 | cut -d: -f1)"
	[ -n "$summarize_line" ] || { echo "wait_and_summarize not called"; false; }
	[ -n "$dev_line" ] || { echo "maybe_dev not called in cs_stack_create"; false; }
	[ "$summarize_line" -lt "$dev_line" ] || { echo "maybe_dev ($dev_line) must run after summarize ($summarize_line)"; false; }
}

# --- worktree create --dev wiring ------------------------------------------

@test "worktree create: --dev is accepted (not an unknown option)" {
	source_worktree
	# stub the remote plumbing so we don't touch a real repo/editor/ssh; we only
	# assert --dev is accepted and forwards to cs_dev on the new worktree path.
	cs_resolve_remote() { echo "white-monster"; }
	cs_create_via_remote_worktree() { echo "REMOTE_WT:$*"; }
	cs_abs_path_from_repo_name_and_branch() { echo "$BATS_TEST_TMPDIR/wt-$1"; }
	cs_dev() { echo "CS_DEV_CALLED:$*"; }
	run cs_worktree_create feat -r white-monster --dev
	assert_success
	# it took the remote worktree path (didn't die on 'unknown option: --dev')
	assert_output --partial "REMOTE_WT:"
	refute_output --partial "unknown option"
	# and forwarded to cs_dev with the resolved worktree path
	assert_output --partial "CS_DEV_CALLED:$BATS_TEST_TMPDIR/wt-feat"
}
