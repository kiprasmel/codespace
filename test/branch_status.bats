#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils

	# "remote" repo with master + a feature branch carrying 3 commits
	REMOTE="$SANDBOX/remote"
	mkrepo "$REMOTE"
	(
		cd "$REMOTE"
		git checkout -q -b pr-feature
		git commit --allow-empty -q -m "pr 1"
		git commit --allow-empty -q -m "pr 2"
		git commit --allow-empty -q -m "pr 3"
		git checkout -q master
	)

	# clone -> CLONE has remote-tracking refs for both branches
	CLONE="$SANDBOX/clone"
	git clone -q "$REMOTE" "$CLONE"
	git -C "$CLONE" config user.email t@e.com
	git -C "$CLONE" config user.name t
}

@test "branch_status: tracking origin/<branch> -> remote with commits ahead" {
	git -C "$CLONE" branch --track pr-feature origin/pr-feature

	run cs_branch_status "$CLONE" pr-feature
	assert_success
	assert_output "remote;origin/master;3"
}

@test "branch_status: no upstream, fresh from base -> new with 0 ahead" {
	git -C "$CLONE" branch --no-track fresh origin/master

	run cs_branch_status "$CLONE" fresh
	assert_success
	assert_output "new;origin/master;0"
}

@test "branch_status: no upstream, commits ahead -> local with count" {
	git -C "$CLONE" branch --no-track local-work origin/master
	git -C "$CLONE" checkout -q local-work
	git -C "$CLONE" commit --allow-empty -q -m "local 1"
	git -C "$CLONE" commit --allow-empty -q -m "local 2"

	run cs_branch_status "$CLONE" local-work
	assert_success
	assert_output "local;origin/master;2"
}

@test "branch_status: explicit bare base resolves to origin/<base>" {
	git -C "$CLONE" branch --track pr-feature origin/pr-feature

	run cs_branch_status "$CLONE" pr-feature master
	assert_success
	assert_output "remote;origin/master;3"
}

@test "branch_status: explicit qualified base used as-is" {
	git -C "$CLONE" branch --track pr-feature origin/pr-feature

	run cs_branch_status "$CLONE" pr-feature origin/master
	assert_success
	assert_output "remote;origin/master;3"
}

@test "branch_status: defaults base to origin/HEAD when omitted" {
	git -C "$CLONE" branch --no-track fresh origin/master

	run cs_branch_status "$CLONE" fresh
	assert_success
	# origin/HEAD points at origin/master (set by clone), so base resolves to origin/master
	assert_output "new;origin/master;0"
}
