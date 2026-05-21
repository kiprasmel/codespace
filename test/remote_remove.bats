#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils
	# also need cs_remove_remote from codespace-worktree
	# shellcheck disable=SC1090
	CS_WORKTREE_NO_RUN=1 source "$REPO_ROOT/codespace-worktree"

	install_ssh_shims
	export SHIM_LOG_STDIN=1

	STUB="$SANDBOX/myorg/myrepo_feat"
	cs_remote_marker_write "$STUB" \
		"host=user@host" \
		"path=\$HOME/codespace/myorg/myrepo_feat" \
		"kind=worktree" \
		"repo_id=myorg/myrepo" \
		"branch=feat"
}

@test "remote_remove: with -f, runs ssh worktree-remove and deletes stub" {
	run cs_remove_remote "$STUB" "1"
	assert_success

	# stub should be gone
	[ ! -d "$STUB" ]

	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"ssh"* ]]
	[[ "$log" == *"user@host"* ]]
	[[ "$log" == *"bash"*"-s"* ]]
	# the cleanup script body should reference worktree remove
	[[ "$log" == *"worktree remove"* ]]
}

@test "remote_remove: clone-kind uses rm -rf path on remote" {
	rm -rf "$STUB"
	cs_remote_marker_write "$STUB" \
		"host=user@host" \
		"path=\$HOME/codespace/myorg/myrepo/feat" \
		"kind=clone" \
		"repo_id=myorg/myrepo" \
		"branch=feat"

	run cs_remove_remote "$STUB" "1"
	assert_success
	[ ! -d "$STUB" ]
}

@test "remote_remove: missing 'host' in marker -> error" {
	rm -rf "$STUB"
	cs_remote_marker_write "$STUB" "kind=worktree" "branch=feat"

	run cs_remove_remote "$STUB" "1"
	assert_failure
	[[ "$output" == *"stub missing 'host'"* ]]
}
