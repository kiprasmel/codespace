#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils
}

@test "remote_relpath: $HOME/<org>/<repo>_<branch> -> codespace/<org>/<repo>_<branch>" {
	run cs_remote_relpath_for_local "$HOME/myorg/myrepo_feat"
	assert_success
	assert_output "codespace/myorg/myrepo_feat"
}

@test "remote_relpath: $HOME -> codespace" {
	run cs_remote_relpath_for_local "$HOME"
	assert_success
	assert_output "codespace"
}

@test "remote_relpath: $HOME/sub -> codespace/sub" {
	run cs_remote_relpath_for_local "$HOME/sub"
	assert_success
	assert_output "codespace/sub"
}

@test "remote_relpath: rejects path outside \$HOME" {
	run cs_remote_relpath_for_local "/etc/passwd"
	assert_failure
	[[ "$output" == *"cannot map path outside"* ]]
}

@test "remote_relpath: works for non-existent paths" {
	# Important: stub paths don't exist yet at the time we compute the rel path
	run cs_remote_relpath_for_local "$HOME/never/created/here"
	assert_success
	assert_output "codespace/never/created/here"
}
