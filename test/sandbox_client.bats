#!/usr/bin/env bats

# Client-side sandbox glue: cloud-repo resolution, the ProxyJump ssh-config
# alias, ensure-over-ssh target parsing, and the `cloud` forward guard. The
# host orchestrator + real DinD are covered by codespace-cloud's own suite and
# Phase A; here we only assert the client composition.

load helpers

setup() {
	common_setup
	source_utils
}

@test "cs_cloud_root honors \$CS_CLOUD_ROOT" {
	CS_CLOUD_ROOT=/some/where run cs_cloud_root
	assert_output "/some/where"
}

@test "cs_cloud_root resolves the sibling codespace-cloud repo" {
	run cs_cloud_root
	assert_success
	assert_output --partial "codespace-cloud"
}

@test "ssh-config writer adds an Include once and a ProxyJump alias block" {
	printf 'Host example\n\tUser bob\n' > "$HOME/.ssh/config" 2>/dev/null || { mkdir -p "$HOME/.ssh"; printf 'Host example\n\tUser bob\n' > "$HOME/.ssh/config"; }

	cs_sandbox_ssh_config_write "cs-sandbox-feat" "white-monster" "49155"

	# user's config preserved + Include prepended exactly once
	run grep -c '^Include config.d/codespace-sandboxes' "$HOME/.ssh/config"
	assert_output "1"
	run grep -c '^Host example' "$HOME/.ssh/config"
	assert_output "1"

	# alias block written to the include file
	run cat "$HOME/.ssh/config.d/codespace-sandboxes"
	assert_output --partial "Host cs-sandbox-feat"
	assert_output --partial "ProxyJump white-monster"
	assert_output --partial "Port 49155"
	assert_output --partial "HostName 127.0.0.1"
}

@test "ssh-config writer refreshes a port without duplicating the block" {
	cs_sandbox_ssh_config_write "cs-sandbox-feat" "white-monster" "1111"
	cs_sandbox_ssh_config_write "cs-sandbox-feat" "white-monster" "2222"
	run grep -c '^Host cs-sandbox-feat' "$HOME/.ssh/config.d/codespace-sandboxes"
	assert_output "1"
	run grep -c '^Include config.d/codespace-sandboxes' "$HOME/.ssh/config"
	assert_output "1"
	run grep '^	Port' "$HOME/.ssh/config.d/codespace-sandboxes"
	assert_output --partial "2222"
	refute_output --partial "1111"
}

@test "cs_sandbox_pubkey returns a default identity" {
	mkdir -p "$HOME/.ssh"
	printf 'ssh-ed25519 AAAAPUB me@mac\n' > "$HOME/.ssh/id_ed25519.pub"
	run cs_sandbox_pubkey
	assert_success
	assert_output "ssh-ed25519 AAAAPUB me@mac"
}

@test "cs_sandbox_remote_ensure parses the target, writes the alias, returns it" {
	mkdir -p "$HOME/.ssh"
	printf 'ssh-ed25519 AAAAPUB me@mac\n' > "$HOME/.ssh/id_ed25519.pub"
	install_ssh_shims
	# log the piped script body too (the orchestrator verb rides on stdin):
	export SHIM_LOG_STDIN=1
	# the host orchestrator would print the ssh-target block:
	export SSH_NEXT_STDOUT=$'alias=cs-sandbox-feature_foo\ncontainer=cs-sandbox-feature_foo\nhostname=127.0.0.1\nport=49177\n'

	run cs_sandbox_remote_ensure white-monster "feature/foo"
	assert_success
	assert_output "cs-sandbox-feature_foo"

	# alias landed in the include file with the parsed port + jump host
	run cat "$HOME/.ssh/config.d/codespace-sandboxes"
	assert_output --partial "Host cs-sandbox-feature_foo"
	assert_output --partial "Port 49177"
	assert_output --partial "ProxyJump white-monster"

	# it invoked the host orchestrator verb over ssh (verb rides on stdin)
	run cat "$SHIM_LOG"
	assert_output --partial "codespace-cloud"
	assert_output --partial "sandbox ensure"
}

@test "cs_cloud_forward errors clearly when the cloud repo is unavailable" {
	CS_CLOUD_ROOT=/definitely/not/here run cs_cloud_forward sandbox ls
	assert_failure
	assert_output --partial "codespace-cloud not available"
}
