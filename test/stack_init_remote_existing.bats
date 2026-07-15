#!/usr/bin/env bats

# cs_stack_init_remote_existing: provision the remote side of an EXISTING local
# stack in parallel (reusing the stack create harness), over the local-remote
# shim. Non-interactive, so it takes the background &/wait path (no tmux).

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

	source_stack
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

_srdir() { echo "$REMOTE_HOME/codespace/myorg/stack_feat/$1"; }

@test "parallel init: provisions every repo's remote worktree" {
	run cs_stack_init_remote_existing "$STACK" user@h
	assert_success

	assert [ -e "$(_srdir repo-a)/.git" ]
	assert [ -e "$(_srdir repo-b)/.git" ]
	# each remote worktree is checked out on the codespace branch
	assert_equal "$(remote_git codespace/myorg/stack_feat/repo-a rev-parse --abbrev-ref HEAD)" feat
	assert_equal "$(remote_git codespace/myorg/stack_feat/repo-b rev-parse --abbrev-ref HEAD)" feat
}

@test "parallel init: does NOT plant per-repo .codespace-remote stubs (sync marker stays authoritative)" {
	run cs_stack_init_remote_existing "$STACK" user@h
	assert_success

	assert [ ! -e "$STACK/repo-a/.codespace-remote" ]
	assert [ ! -e "$STACK/repo-b/.codespace-remote" ]
}

@test "parallel init: tolerates the existing non-empty local worktrees" {
	# the worktrees already have content + .git; the old guard refused that.
	assert [ -n "$(ls -A "$STACK/repo-a")" ]
	run cs_stack_init_remote_existing "$STACK" user@h
	assert_success
}

@test "repo_remote_host: stack-level marker resolves host when no per-repo stub" {
	stack_dir="$STACK"
	export remote_host="user@h"
	export stack_dest_rel="codespace/myorg/stack_feat"
	export branch="feat"
	cs_stack_write_remote_marker

	run cs_stack_repo_remote_host "$STACK/repo-a" "$STACK"
	assert_success
	assert_output "user@h"
}

@test "print_repo_status: local worktrees still use cs_branch_status after init-remote" {
	cs_stack_init_remote_existing "$STACK" user@h 2>&1 | tee "$BATS_TEST_TMPDIR/init.out"

	grep -q "repo-a" "$BATS_TEST_TMPDIR/init.out"
	grep -q "new (origin/master)" "$BATS_TEST_TMPDIR/init.out"
	! grep -q "remote @" "$BATS_TEST_TMPDIR/init.out"
}
