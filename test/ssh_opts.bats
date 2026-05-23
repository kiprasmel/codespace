#!/usr/bin/env bats

# cs_ssh_opts — options string shared by all ssh/rsync calls in the create flow.

load helpers

setup() {
	common_setup
	source_utils
}

@test "ssh_opts: forwards the agent (so remote git ops can use local keys)" {
	run cs_ssh_opts
	assert_success
	[[ "$output" == *"-o ForwardAgent=yes"* ]]
}

@test "ssh_opts: still uses BatchMode + ControlMaster persistence" {
	run cs_ssh_opts
	assert_success
	[[ "$output" == *"-o BatchMode=yes"* ]]
	[[ "$output" == *"-o ControlMaster=auto"* ]]
	[[ "$output" == *"-o ControlPersist=60"* ]]
	[[ "$output" == *"-o ControlPath=$HOME/.ssh/"* ]]
}
