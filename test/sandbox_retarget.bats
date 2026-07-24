#!/usr/bin/env bats

# Client-side sandbox RETARGET glue: the CS_SANDBOX gate, cs_sandbox_retarget
# (ensure + export CS_WORKTREE_BASE + pick the alias as $host), the marker
# fields recovered from the ssh-config alias, and the tmux-hop env prefix.
# The host orchestrator + real DinD are covered by codespace-cloud's suite and
# Phase A; here we only assert the client composition + the auto-on default /
# opt-out safety.

load helpers

setup() {
	common_setup
	source_utils
	mkdir -p "$HOME/.ssh"
	printf 'ssh-ed25519 AAAAPUB me@mac\n' > "$HOME/.ssh/id_ed25519.pub"
}

# canned host-orchestrator `sandbox ensure` reply for the ssh shim
ensure_reply() {
	printf 'alias=%s\ncontainer=%s\nhostname=127.0.0.1\nport=%s\n' \
		"cs-sandbox-feature_foo" "cs-sandbox-feature_foo" "49177"
}

@test "cs_sandbox_active: ON by default (auto) when the module is loaded" {
	declare -f cs_sandbox_workspace_root >/dev/null   # module IS loaded here
	run cs_sandbox_active
	assert_success
}

@test "cs_sandbox_active: truthy stays on; explicit opt-out (0|false|no|off) turns it off" {
	CS_SANDBOX=1 run cs_sandbox_active
	assert_success
	CS_SANDBOX=yes run cs_sandbox_active
	assert_success
	local v
	for v in 0 false no off; do
		CS_SANDBOX="$v" run cs_sandbox_active
		assert_failure
	done
}

@test "cs_sandbox_retarget: ensures the sandbox, exports the base, picks the alias" {
	install_ssh_shims
	export SHIM_LOG_STDIN=1
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT

	# called directly (not via `run`) so its exports land in this shell
	cs_sandbox_retarget white-monster "feature/foo"

	[ "$CS_SANDBOX_ALIAS" = "cs-sandbox-feature_foo" ]
	[ "$CS_WORKTREE_BASE" = "/codespaces/feature_foo" ]
	# exported (a subshell sees it)
	run bash -c 'echo "$CS_WORKTREE_BASE"'
	assert_output "/codespaces/feature_foo"

	# the alias landed in the include with the parsed port + jump host
	run cat "$HOME/.ssh/config.d/codespace-sandboxes"
	assert_output --partial "Host cs-sandbox-feature_foo"
	assert_output --partial "Port 49177"
	assert_output --partial "ProxyJump white-monster"
	# it drove the host orchestrator verb over ssh
	run cat "$SHIM_LOG"
	assert_output --partial "sandbox ensure"
}

@test "cs_sandbox_marker_fields: recovers sandbox id/host/port + base from the alias" {
	install_ssh_shims
	export SHIM_LOG_STDIN=1
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT
	cs_sandbox_retarget white-monster "feature/foo"

	run cs_sandbox_marker_fields "$CS_SANDBOX_ALIAS"
	assert_success
	assert_line "sandbox=cs-sandbox-feature_foo"
	assert_line "sandbox_host=white-monster"
	assert_line "sandbox_port=49177"
	assert_line "worktree_base=/codespaces/feature_foo"
}

@test "cs_sandbox_marker_fields: empty in host-FS mode (no CS_WORKTREE_BASE)" {
	run cs_sandbox_marker_fields "white-monster"
	assert_success
	assert_output ""
}

@test "cs_sandbox_marker_fields: empty for a non-sandbox host even if base is set" {
	CS_WORKTREE_BASE=/codespaces/x run cs_sandbox_marker_fields "plain-host"
	assert_success
	assert_output ""
}

@test "cs_remote_child_env_prefix: carries the base in sandbox mode, empty otherwise" {
	run cs_remote_child_env_prefix
	assert_output ""

	CS_WORKTREE_BASE=/codespaces/feature_foo run cs_remote_child_env_prefix
	assert_output "CS_WORKTREE_BASE=/codespaces/feature_foo "
}

# --- the actual codespace-stack wiring choke-point ---------------------------

@test "cs_stack_create_retarget_sandbox: explicit opt-out (CS_SANDBOX=0) is a no-op (no ensure)" {
	source_stack
	install_ssh_shims
	export CS_SANDBOX=0
	remote_host="white-monster"; branch="feature/foo"
	cs_stack_create_retarget_sandbox
	[ "$remote_host" = "white-monster" ]      # untouched
	[ -z "${CS_WORKTREE_BASE:-}" ]            # host-FS: base stays unset
	run cat "$SHIM_LOG"
	refute_output --partial "sandbox ensure"  # never drove the orchestrator
}

@test "cs_stack_create_retarget_sandbox: sandbox mode retargets \$host + exports base" {
	source_stack
	install_ssh_shims
	export SHIM_LOG_STDIN=1
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT
	export CS_SANDBOX=1
	remote_host="white-monster"; branch="feature/foo"
	cs_stack_create_retarget_sandbox
	[ "$remote_host" = "cs-sandbox-feature_foo" ]
	[ "$CS_WORKTREE_BASE" = "/codespaces/feature_foo" ]
	run cat "$SHIM_LOG"
	assert_output --partial "sandbox ensure"
}
