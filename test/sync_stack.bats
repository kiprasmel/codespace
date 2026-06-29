#!/usr/bin/env bats

# End-to-end `codespace sync` for a multi-repo stack against the local-remote
# harness: per-repo provision + commit-align, stack-root loose files, stack
# marker, and per-repo conflict reporting.

load helpers

setup() {
	common_setup
	setup_local_remote
	export CS_NO_EDIT=1

	mkdir -p "$SANDBOX/myorg"
	_mkrepo_origin repo-a
	_mkrepo_origin repo-b

	STACK="$SANDBOX/myorg/stack_feat"
	mkdir -p "$STACK"
	git -C "$SANDBOX/myorg/repo-a" worktree add -q "$STACK/repo-a" feat
	git -C "$SANDBOX/myorg/repo-b" worktree add -q "$STACK/repo-b" feat
	cd "$STACK"
}

_mkrepo_origin() {
	local name="$1"
	git init -q --bare "$SANDBOX/$name.git"
	git clone -q "$SANDBOX/$name.git" "$SANDBOX/myorg/$name" 2>/dev/null
	(
		cd "$SANDBOX/myorg/$name"
		git config user.email t@e.com && git config user.name t
		echo "$name" > f.txt
		git add -A && git commit -q -m init
		git push -q origin master
		git branch feat
	)
}

# remote worktree dir for a stack repo
_srdir() { echo "$REMOTE_HOME/codespace/myorg/stack_feat/$1"; }

@test "stack sync: provisions every repo, aligns each, ships loose files, marks stack" {
	( cd "$STACK/repo-a" && echo a1 >> f.txt && git add -A && git commit -q -m "a1" )
	( cd "$STACK/repo-b" && echo b1 >> f.txt && git add -A && git commit -q -m "b1" )
	echo "shared" > AGENTS.md

	run codespace sync -r user@h
	assert_success

	[ -e "$(_srdir repo-a)/.git" ]
	[ -e "$(_srdir repo-b)/.git" ]
	[ "$(git -C "$STACK/repo-a" rev-parse HEAD)" = "$(remote_git codespace/myorg/stack_feat/repo-a rev-parse HEAD)" ]
	[ "$(git -C "$STACK/repo-b" rev-parse HEAD)" = "$(remote_git codespace/myorg/stack_feat/repo-b rev-parse HEAD)" ]
	[ -f "$REMOTE_HOME/codespace/myorg/stack_feat/AGENTS.md" ]

	run grep '^kind=' "$STACK/.codespace/sync"
	assert_output "kind=stack"
}

@test "stack sync: re-sync remembers host from the stack marker" {
	run codespace sync -r user@h
	assert_success

	( cd "$STACK/repo-a" && echo a2 >> f.txt && git add -A && git commit -q -m "a2" )
	run codespace sync
	assert_success
	[ "$(git -C "$STACK/repo-a" rev-parse HEAD)" = "$(remote_git codespace/myorg/stack_feat/repo-a rev-parse HEAD)" ]
}

@test "stack watch: foreground -w shows aggregated status (bounded), every repo live" {
	install_mutagen_shim
	force_interactive
	export CS_WATCH_POLL_MAX=1 CS_WATCH_POLL_INTERVAL=0

	run codespace sync -r user@h -w
	assert_success
	assert_output --partial "live sync active for stack 'feat'"

	run grep -c '^mutagen_session=' "$STACK/repo-a/.codespace/sync"
	assert_output "1"
	run grep -c '^mutagen_session=' "$STACK/repo-b/.codespace/sync"
	assert_output "1"
}

@test "stack sync: a per-repo conflict is reported; other repos still sync" {
	run codespace sync -r user@h
	assert_success

	# repo-a diverges with a conflicting change on the same file
	echo remoteline > "$(_srdir repo-a)/f.txt"
	remote_git codespace/myorg/stack_feat/repo-a commit -qam "remote conflicting"
	( cd "$STACK/repo-a" && echo localline > f.txt && git add -A && git commit -q -m "local conflicting" )

	# repo-b advances cleanly
	( cd "$STACK/repo-b" && echo b2 >> f.txt && git add -A && git commit -q -m "b2" )

	run codespace sync
	assert_failure
	assert_output --partial "conflicts"
	assert_output --partial "repo-a"

	# repo-b still converged
	[ "$(git -C "$STACK/repo-b" rev-parse HEAD)" = "$(remote_git codespace/myorg/stack_feat/repo-b rev-parse HEAD)" ]
}
