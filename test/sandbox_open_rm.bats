#!/usr/bin/env bats

# open/rm on a SANDBOX-backed stub. The stub's .codespace-remote marker carries
# the sandbox fields cs_sandbox_marker_fields stamps at create (sandbox=,
# sandbox_host=, sandbox_port=, worktree_base=), so open + rm must (re)ensure the
# container first (start it if stopped, refresh the ssh alias' port, export
# CS_WORKTREE_BASE) before they can reach it. `rm` on the STACK stub tears the
# whole sandbox down (work volume kept by default, dropped with --prune-volume);
# a per-repo stub only removes its worktree and leaves the sandbox running.
#
# The host orchestrator + real DinD live in codespace-cloud's suite + Phase A;
# here we assert the client composition with shimmed ssh.

load helpers

setup() {
	common_setup
	source_find                       # cs_open_path + cs_remove_remote + sandbox glue
	mkdir -p "$HOME/.ssh"
	printf 'ssh-ed25519 AAAAPUB me@mac\n' > "$HOME/.ssh/id_ed25519.pub"
	install_ssh_shims
	export SHIM_LOG_STDIN=1
	export CS_NO_EDIT=1
}

# canned host-orchestrator `sandbox ensure` reply for the ssh shim (re-ensure)
ensure_reply() {
	printf 'alias=%s\ncontainer=%s\nhostname=127.0.0.1\nport=%s\n' \
		"cs-sandbox-feature_foo" "cs-sandbox-feature_foo" "49177"
}

# marker for a sandbox-backed stub of the given kind (default: whole-stack stub)
write_sandbox_marker() {
	local dir="$1" kind="${2:-stack}"
	cs_remote_marker_write "$dir" \
		"host=cs-sandbox-feature_foo" \
		"relpath=codespace/sintra/stack_feature_foo" \
		"kind=$kind" \
		"repo_id=sintra/core" \
		"branch=feature/foo" \
		"sandbox=cs-sandbox-feature_foo" \
		"sandbox_host=white-monster" \
		"sandbox_port=49177" \
		"worktree_base=/codespaces/feature_foo"
}

# --- detection ---------------------------------------------------------------

@test "cs_remote_marker_is_sandbox: true with sandbox fields, false for a plain stub" {
	D="$SANDBOX/s"; write_sandbox_marker "$D"
	run cs_remote_marker_is_sandbox "$D"
	assert_success

	P="$SANDBOX/p"
	cs_remote_marker_write "$P" "host=user@host" "relpath=codespace/x" "kind=worktree"
	run cs_remote_marker_is_sandbox "$P"
	assert_failure
}

# --- re-ensure ---------------------------------------------------------------

@test "cs_remote_reensure_sandbox: re-ensures from the marker + retargets base/alias" {
	D="$SANDBOX/s"; write_sandbox_marker "$D"
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT

	# called directly (not via `run`) so its exports land in this shell
	cs_remote_reensure_sandbox "$D"
	[ "$CS_SANDBOX_ALIAS" = "cs-sandbox-feature_foo" ]
	[ "$CS_WORKTREE_BASE" = "/codespaces/feature_foo" ]

	run cat "$SHIM_LOG"
	assert_output --partial "sandbox ensure"
	# the refreshed alias landed in the ssh include with the parsed port + jump
	run cat "$HOME/.ssh/config.d/codespace-sandboxes"
	assert_output --partial "Host cs-sandbox-feature_foo"
	assert_output --partial "Port 49177"
	assert_output --partial "ProxyJump white-monster"
}

@test "cs_remote_reensure_sandbox: a plain (non-sandbox) stub returns non-zero, ensures nothing" {
	P="$SANDBOX/p"
	cs_remote_marker_write "$P" "host=user@host" "relpath=codespace/x" "kind=worktree" "branch=x"
	run cs_remote_reensure_sandbox "$P"
	assert_failure
	run cat "$SHIM_LOG"
	refute_output --partial "sandbox ensure"
}

# --- teardown ----------------------------------------------------------------

@test "cs_sandbox_remote_teardown: ssh's the JUMP host with 'sandbox rm <slug>'" {
	D="$SANDBOX/s"; write_sandbox_marker "$D"
	run cs_sandbox_remote_teardown "$D"
	assert_success
	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"white-monster"* ]]    # driven on the jump host, not the alias
	[[ "$log" == *"sandbox rm"* ]]       # orchestrator teardown verb (script body)
	[[ "$log" == *"feature_foo"* ]]      # slug (derived from the alias) passed along
}

@test "cs_sandbox_remote_teardown: no-op success when the stub isn't sandbox-backed" {
	P="$SANDBOX/p"
	cs_remote_marker_write "$P" "host=user@host" "relpath=codespace/x" "kind=stack"
	run cs_sandbox_remote_teardown "$P"
	assert_success
	run cat "$SHIM_LOG"
	refute_output --partial "sandbox rm"
}

# --- rm ----------------------------------------------------------------------

@test "cs_remove_remote: sandbox STACK stub re-ensures then tears the sandbox down (work volume kept)" {
	D="$SANDBOX/sintra/stack_feature_foo"; write_sandbox_marker "$D" stack
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT

	run cs_remove_remote "$D" 1          # force=1 -> skip the git safety check
	assert_success
	[ ! -d "$D" ]                        # local stub removed
	assert_output --partial "work volume kept"

	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"sandbox ensure"* ]]   # re-ensured to reach it first
	[[ "$log" == *"sandbox rm"* ]]       # then tore the whole sandbox down
	[[ "$log" != *"worktree remove"* ]]  # NOT per-worktree surgery
}

@test "cs_remove_remote: sandbox STACK stub with --prune-volume also drops the work volume" {
	D="$SANDBOX/sintra/stack_feature_foo"; write_sandbox_marker "$D" stack
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT

	run cs_remove_remote "$D" 1 1        # force=1, prune=1
	assert_success
	assert_output --partial "container + work volume"
}

@test "cs_remove_remote: sandbox per-repo (worktree) stub removes the worktree, leaves the sandbox up" {
	D="$SANDBOX/sintra/stack_feature_foo/core"; write_sandbox_marker "$D" worktree
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT

	run cs_remove_remote "$D" 1
	assert_success
	[ ! -d "$D" ]

	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"sandbox ensure"* ]]   # re-ensured to reach it
	[[ "$log" == *"worktree remove"* ]]  # per-worktree removal inside the sandbox
	[[ "$log" != *"sandbox rm"* ]]       # the shared sandbox is left running
}

# --- open --------------------------------------------------------------------

@test "cs_open_path: sandbox-backed stub re-ensures the container before opening" {
	D="$SANDBOX/sintra/stack_feature_foo"; write_sandbox_marker "$D" stack
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT

	# non-GUI editor -> prints the manual ssh hint (no cs_remote_abs round-trip),
	# so we can assert the re-ensure + retargeted alias without a real editor.
	GUI_EDITOR="" EDITOR="" run cs_open_path "$D"
	assert_success

	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"sandbox ensure"* ]]   # re-ensured before opening
	# the hint targets the refreshed sandbox alias
	assert_output --partial "cs-sandbox-feature_foo"
}
