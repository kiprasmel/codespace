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

_prefetch_and_print_status() {
	cs_stack_prefetch_remote_statuses "$@"
	cs_stack_print_repo_status "$@"
}

_write_stub() {
	local name="$1" host="$2"
	cs_remote_marker_write "$STACK/$name" \
		"host=$host" \
		"relpath=codespace/myorg/stack_feat/$name" \
		"kind=worktree" \
		"repo_id=myorg/$name" \
		"branch=feat"
}

_mock_remote_status_new() {
	local host="$1"; shift
	local spec name
	for spec in "$@"; do
		IFS='|' read -r name _ <<< "$spec"
		echo "$name;new;origin/master;0"
	done
}

@test "print_repo_status: local worktree uses cs_branch_status" {
	mkrepo "$SANDBOX/myorg/repo-a"
	git -C "$SANDBOX/myorg/repo-a" branch -q feat
	git -C "$SANDBOX/myorg/repo-a" worktree add -q "$STACK/repo-a" feat

	run _print_status
	assert_success
	assert_output --partial "repo-a"
	assert_output --partial "new  (origin/master)"
	refute_output --partial "remote @"
}

@test "print_repo_status: remote stub shows verified state, base, and host" {
	_write_stub repo-a white-monster
	cs_stack_remote_branch_status_batch() { _mock_remote_status_new "$@"; }

	run _prefetch_and_print_status
	assert_success
	assert_output "    repo-a  new  (origin/master)  @white-monster"
}

@test "print_repo_status: failed remote stub shows (failed)" {
	_write_stub repo-a white-monster
	cs_stack_remote_branch_status_batch() {
		touch "$BATS_TEST_TMPDIR/remote-status-queried"
		_mock_remote_status_new "$@"
	}

	run _prefetch_and_print_status repo-a
	assert_success
	assert_output "    repo-a  (failed)"
	[ ! -e "$BATS_TEST_TMPDIR/remote-status-queried" ]
}

@test "print_repo_status: extend resolves host from per-repo marker without remote_host global" {
	unset remote_host
	_write_stub repo-a user@extend-host
	cs_stack_remote_branch_status_batch() { _mock_remote_status_new "$@"; }

	run _prefetch_and_print_status
	assert_success
	assert_output "    repo-a  new  (origin/master)  @user@extend-host"
}

@test "print_repo_status: maps tracked and unpushed remote branches without overloaded location labels" {
	repo_names=(tracked unpushed)
	repo_dests=("$STACK/tracked" "$STACK/unpushed")
	_write_stub tracked white-monster
	_write_stub unpushed white-monster
	cs_stack_remote_status_set tracked "remote;origin/master;0"
	cs_stack_remote_status_set unpushed "local;origin/master;4"

	run _print_status
	assert_success
	assert_output $'    tracked   existing     (origin/master)  @white-monster\n    unpushed  unpublished  (origin/master)  @white-monster'
	refute_output --partial "remote "
	refute_output --partial "local "
}

@test "print_repo_status: aligns repo, state, base, and host columns without trailing whitespace" {
	repo_names=(codespace codespace-cloud api jobs worker)
	repo_dests=("$STACK/codespace" "$STACK/codespace-cloud" "$STACK/api" "$STACK/jobs" "$STACK/worker")
	_write_stub codespace white-monster
	_write_stub codespace-cloud white-monster
	_write_stub jobs white-monster
	mkdir -p "$STACK/api" "$STACK/worker"
	touch "$STACK/api/.git"
	cs_branch_status() { echo "local;origin/main;12"; }
	cs_stack_remote_status_set codespace "new;origin/master;0"
	cs_stack_remote_status_set codespace-cloud "remote;origin/master;0"
	cs_stack_remote_status_set jobs "local;origin/main;3"

	run _print_status worker
	assert_success
	assert_output $'    codespace        new          (origin/master)  @white-monster\n    codespace-cloud  existing     (origin/master)  @white-monster\n    api              local +12    (origin/main)\n    jobs             unpublished  (origin/main)    @white-monster\n    worker           (failed)'
	while IFS= read -r line; do
		[[ "$line" != *" " ]]
	done <<< "$output"
}

@test "print_repo_status: ssh failure shows unknown state at the resolved host" {
	_write_stub repo-a white-monster
	cs_stack_remote_branch_status_batch() { return 1; }

	run _prefetch_and_print_status
	assert_success
	assert_output "    repo-a  ?  @white-monster"
}

@test "prefetch_remote_statuses: batches all repos into one query per host" {
	repo_names=(repo-a repo-b repo-c)
	repo_dests=("$STACK/repo-a" "$STACK/repo-b" "$STACK/repo-c")
	_write_stub repo-a host-one
	_write_stub repo-b host-one
	_write_stub repo-c host-two
	cs_stack_remote_branch_status_batch() {
		local host="$1"; shift
		echo "$host:$#" >> "$BATS_TEST_TMPDIR/remote-status-calls"
		_mock_remote_status_new "$host" "$@"
	}

	run _prefetch_and_print_status
	assert_success
	assert_equal "$(wc -l < "$BATS_TEST_TMPDIR/remote-status-calls" | xargs)" 2
	grep -qx "host-one:2" "$BATS_TEST_TMPDIR/remote-status-calls"
	grep -qx "host-two:1" "$BATS_TEST_TMPDIR/remote-status-calls"
}

@test "print_repo_status: empty dir without git or marker shows ?" {
	mkdir -p "$STACK/repo-a"

	run _print_status
	assert_success
	assert_output --regexp 'repo-a[[:space:]]+\?'
}

@test "print_repo_status: queries real remote git state through one batched ssh call" {
	setup_local_remote
	local seed="$SANDBOX/seed" origin="$SANDBOX/repo-a.git"
	local remote_base="$REMOTE_HOME/codespace/myorg/repo-a"
	local remote_dest="$REMOTE_HOME/codespace/myorg/stack_feat/repo-a"
	mkrepo "$seed"
	git clone -q --bare "$seed" "$origin"
	git clone -q "$origin" "$remote_base"
	git -C "$remote_base" branch --no-track feat origin/master
	mkdir -p "$(dirname "$remote_dest")"
	git -C "$remote_base" worktree add -q "$remote_dest" feat
	_write_stub repo-a user@h

	run _prefetch_and_print_status
	assert_success
	assert_output "    repo-a  new  (origin/master)  @user@h"
}

@test "print_repo_status: missing remote checkout never falls through to new" {
	setup_local_remote
	_write_stub repo-a user@h

	run _prefetch_and_print_status
	assert_success
	assert_output "    repo-a  ?  @user@h"
	refute_output --partial "new"
}
