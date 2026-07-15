#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack

	STACK="$SANDBOX/myorg/stack_feat"
	mkdir -p "$STACK"
	stack_dir="$STACK"
	branch="feat"
	repo_names=(repo-a)
	repo_dests=("$STACK/repo-a")
}

_print_status() {
	# shellcheck disable=SC2068
	cs_stack_print_repo_status "$@"
}

@test "print_repo_status: local worktree uses cs_branch_status" {
	mkrepo "$SANDBOX/myorg/repo-a"
	git -C "$SANDBOX/myorg/repo-a" branch -q feat
	git -C "$SANDBOX/myorg/repo-a" worktree add -q "$STACK/repo-a" feat

	run _print_status
	assert_success
	assert_output --partial "repo-a"
	assert_output --partial "new (origin/master)"
	refute_output --partial "remote @"
}

@test "print_repo_status: remote stub shows remote @host" {
	mkdir -p "$STACK/repo-a"
	cs_remote_marker_write "$STACK/repo-a" \
		"host=white-monster" \
		"relpath=codespace/myorg/stack_feat/repo-a" \
		"kind=worktree" \
		"repo_id=myorg/repo-a" \
		"branch=feat"

	run _print_status
	assert_success
	assert_output --partial "repo-a"
	assert_output --partial "remote @white-monster"
	refute_output --partial "origin/master"
}

@test "print_repo_status: failed remote stub shows (failed)" {
	mkdir -p "$STACK/repo-a"
	cs_remote_marker_write "$STACK/repo-a" \
		"host=white-monster" \
		"relpath=codespace/myorg/stack_feat/repo-a" \
		"kind=worktree"

	run _print_status repo-a
	assert_success
	assert_output --partial "(failed)"
	refute_output --partial "remote @"
}

@test "print_repo_status: extend resolves host from per-repo marker without remote_host global" {
	unset remote_host
	mkdir -p "$STACK/repo-a"
	cs_remote_marker_write "$STACK/repo-a" \
		"host=user@extend-host" \
		"relpath=codespace/myorg/stack_feat/repo-a" \
		"kind=worktree"

	run _print_status
	assert_success
	assert_output --partial "remote @user@extend-host"
}

@test "print_repo_status: empty dir without git or marker shows ?" {
	mkdir -p "$STACK/repo-a"

	run _print_status
	assert_success
	assert_output --regexp 'repo-a[[:space:]]+\?'
}
