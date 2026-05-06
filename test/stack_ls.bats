#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_stack

	ORG="$SANDBOX/org"
	REMOTES="$SANDBOX/remotes"
	mkdir -p "$ORG" "$REMOTES"
}

# --- fixtures ----------------------------------------------------------------

# create a repo at $ORG/<name> with a bare origin remote that has master,
# origin/HEAD pointing at master, and master tracking origin/master.
mk_repo_with_origin() {
	local name="$1"
	local repo="$ORG/$name"
	local remote="$REMOTES/$name.git"

	git init --bare -q "$remote"
	mkrepo "$repo"
	git -C "$repo" remote add origin "$remote"
	git -C "$repo" push -q origin master
	# pin origin/HEAD so cs_get_default_branch resolves to master regardless
	# of what branch is currently checked out in any worktree.
	git -C "$repo" remote set-head origin master
	git -C "$repo" branch --set-upstream-to=origin/master master >/dev/null
}

# add a worktree at $ORG/stack_<branch>/<repo> for each <repo>. creates the
# branch if it doesn't exist yet, otherwise reuses the existing one.
# args: branch repo [repo2...]
mk_stack() {
	local branch="$1"; shift
	local stack_dir="$ORG/stack_$branch"
	mkdir -p "$stack_dir"
	for repo in "$@"; do
		local base="$ORG/$repo"
		if git -C "$base" show-ref --verify --quiet "refs/heads/$branch"; then
			git -C "$base" worktree add -q "$stack_dir/$repo" "$branch"
		else
			git -C "$base" worktree add -q "$stack_dir/$repo" -b "$branch"
		fi
	done
	echo "$stack_dir"
}

# --- listing -----------------------------------------------------------------

@test "ls: lists every stack in the current org with branch + age" {
	mk_repo_with_origin repo-a
	mk_stack feat1 repo-a
	mk_stack feat2 repo-a

	cd "$ORG"
	run cs_stack_ls
	assert_success
	assert_output --partial "$ORG/stack_feat1"
	assert_output --partial "$ORG/stack_feat2"
	assert_output --partial "branch=feat1"
	assert_output --partial "branch=feat2"
	assert_output --partial "age="
}

@test "ls: --quiet prints only paths" {
	mk_repo_with_origin repo-a
	mk_stack feat1 repo-a

	cd "$ORG"
	run cs_stack_ls --quiet
	assert_success
	assert_output "$ORG/stack_feat1"
}

@test "ls: works when run from inside a stack repo (resolves org via git common-dir)" {
	mk_repo_with_origin repo-a
	mk_stack feat1 repo-a

	# from inside a worktree, cs_stack_get_org_dir resolves through git, which
	# canonicalizes /var -> /private/var on macOS. compare against realpath.
	local real_org
	real_org="$(realpath "$ORG")"

	cd "$ORG/stack_feat1/repo-a"
	run cs_stack_ls --quiet
	assert_success
	assert_output "$real_org/stack_feat1"
}

@test "ls: empty org -> success, no output" {
	cd "$ORG"
	run cs_stack_ls
	assert_success
	assert_output ""
}

# --- --older-than -----------------------------------------------------------

@test "ls --older-than: keeps old, drops fresh" {
	mk_repo_with_origin repo-a
	local old_stack fresh_stack
	old_stack="$(mk_stack old repo-a)"
	fresh_stack="$(mk_stack fresh repo-a)"

	# backdate the old stack dir mtime
	touch -t 202001010000 "$old_stack"

	cd "$ORG"
	run cs_stack_ls --older-than 30d --quiet
	assert_success
	assert_output "$old_stack"
}

@test "ls --older-than: rejects bogus duration" {
	cd "$ORG"
	run --separate-stderr cs_stack_ls --older-than nonsense
	assert_failure
	[[ "$stderr" == *"invalid duration"* ]]
}

# --- --integrated -----------------------------------------------------------

@test "ls --integrated: keeps stacks where every branch is ancestor of origin/<default>" {
	mk_repo_with_origin repo-a
	# create feat at master and push so origin/feat exists too.
	git -C "$ORG/repo-a" branch feat master
	git -C "$ORG/repo-a" push -q origin feat
	mk_stack feat repo-a

	cd "$ORG"
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "stack_feat"
	assert_output --partial "integrated=1/1"
}

@test "ls --integrated: drops stacks with branches divergent from origin/<default>" {
	mk_repo_with_origin repo-a
	mk_stack feat repo-a

	# advance feat past master with a new commit in the worktree
	git -C "$ORG/stack_feat/repo-a" commit -q --allow-empty -m "extra"

	cd "$ORG"
	run cs_stack_ls --integrated --quiet
	assert_success
	assert_output ""
}

@test "ls --integrated: requires every repo in the stack to be integrated" {
	mk_repo_with_origin repo-a
	mk_repo_with_origin repo-b
	mk_stack mix repo-a repo-b

	# advance only repo-b's branch -> repo-a integrated, repo-b not.
	git -C "$ORG/stack_mix/repo-b" commit -q --allow-empty -m "extra"

	cd "$ORG"
	run cs_stack_ls --integrated --quiet
	assert_success
	# whole stack excluded because not every repo is integrated
	assert_output ""
}

# --- --by-commit-age --------------------------------------------------------

@test "ls --by-commit-age: uses git log timestamp, not dir mtime" {
	mk_repo_with_origin repo-a
	local stack
	stack="$(mk_stack feat repo-a)"

	# backdate stack dir mtime; the branch tip commit is still "now"
	touch -t 202001010000 "$stack"

	cd "$ORG"

	# without --by-commit-age, dir mtime says it's old -> kept
	run cs_stack_ls --older-than 30d --quiet
	assert_success
	assert_output "$stack"

	# with --by-commit-age, branch is fresh -> dropped
	run cs_stack_ls --by-commit-age --older-than 30d --quiet
	assert_success
	assert_output ""
}

# --- --global ---------------------------------------------------------------

@test "ls --global: scans every org registered under CODESPACE_CONFIG_ROOT" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"

	# stand up two distinct orgs each with one stack
	local ORG1="$SANDBOX/work" ORG2="$SANDBOX/play"
	for o in "$ORG1" "$ORG2"; do mkdir -p "$o"; done

	# register both orgs in the user config tree (mirrors layout)
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/work/stacks.json"
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/play/.codespace/stacks.json"

	# org 1: repo + stack
	git init --bare -q "$REMOTES/r1.git"
	mkrepo "$ORG1/r1"
	git -C "$ORG1/r1" remote add origin "$REMOTES/r1.git"
	git -C "$ORG1/r1" push -q origin master
	git -C "$ORG1/r1" remote set-head origin master
	mkdir -p "$ORG1/stack_w1"
	git -C "$ORG1/r1" worktree add -q "$ORG1/stack_w1/r1" -b w1

	# org 2: repo + stack
	git init --bare -q "$REMOTES/r2.git"
	mkrepo "$ORG2/r2"
	git -C "$ORG2/r2" remote add origin "$REMOTES/r2.git"
	git -C "$ORG2/r2" push -q origin master
	git -C "$ORG2/r2" remote set-head origin master
	mkdir -p "$ORG2/stack_p1"
	git -C "$ORG2/r2" worktree add -q "$ORG2/stack_p1/r2" -b p1

	# run from one org: --global should pick up both
	cd "$ORG1"
	run cs_stack_ls --global --quiet
	assert_success
	assert_output --partial "$ORG1/stack_w1"
	assert_output --partial "$ORG2/stack_p1"
}

@test "ls --global: warns and falls back to current org if CODESPACE_CONFIG_ROOT unset" {
	mk_repo_with_origin repo-a
	mk_stack feat1 repo-a

	cd "$ORG"
	run --separate-stderr cs_stack_ls --global --quiet
	assert_success
	assert_output "$ORG/stack_feat1"
	[[ "$stderr" == *"CODESPACE_CONFIG_ROOT"* ]]
}

# --- --rm -------------------------------------------------------------------

@test "ls --rm: deletes a stack whose repos are all safe" {
	mk_repo_with_origin repo-a
	# create + push feat so safety check finds an upstream with no unpushed
	git -C "$ORG/repo-a" branch feat master
	git -C "$ORG/repo-a" push -q origin feat
	mk_stack feat repo-a
	git -C "$ORG/stack_feat/repo-a" branch --set-upstream-to=origin/feat >/dev/null

	cd "$ORG"
	run cs_stack_ls --rm
	assert_success
	assert [ ! -d "$ORG/stack_feat" ]

	# worktree registration should be cleaned up too
	run git -C "$ORG/repo-a" worktree list --porcelain
	assert_success
	refute_output --partial "stack_feat/repo-a"
}

@test "ls --rm: skips a stack that has untracked files" {
	mk_repo_with_origin repo-a
	git -C "$ORG/repo-a" branch feat master
	git -C "$ORG/repo-a" push -q origin feat
	mk_stack feat repo-a
	git -C "$ORG/stack_feat/repo-a" branch --set-upstream-to=origin/feat >/dev/null

	# make it unsafe
	touch "$ORG/stack_feat/repo-a/leftover.txt"

	cd "$ORG"
	run --separate-stderr cs_stack_ls --rm
	assert_success
	assert [ -d "$ORG/stack_feat" ]
	[[ "$stderr" == *"skip (unsafe repos)"* ]]
}

@test "ls --rm: filters compose with --integrated (only deletes merged stacks)" {
	mk_repo_with_origin repo-a

	# integrated stack: feat == master, both pushed
	git -C "$ORG/repo-a" branch feat master
	git -C "$ORG/repo-a" push -q origin feat
	mk_stack feat repo-a
	git -C "$ORG/stack_feat/repo-a" branch --set-upstream-to=origin/feat >/dev/null

	# divergent stack: wip ahead of master
	mk_stack wip repo-a
	git -C "$ORG/stack_wip/repo-a" commit -q --allow-empty -m "wip"

	cd "$ORG"
	run cs_stack_ls --integrated --rm
	assert_success
	assert [ ! -d "$ORG/stack_feat" ]
	assert [ -d "$ORG/stack_wip" ]
}

# --- argument validation ----------------------------------------------------

@test "ls: rejects unknown flags" {
	cd "$ORG"
	run --separate-stderr cs_stack_ls --bogus
	assert_failure
	[[ "$stderr" == *"unknown argument"* ]]
}

# --- standalone executable --------------------------------------------------

@test "standalone: ./codespace-stack-ls behaves like 'codespace stack ls'" {
	mk_repo_with_origin repo-a
	mk_stack feat1 repo-a

	cd "$ORG"
	run "$REPO_ROOT/codespace-stack-ls" --quiet
	assert_success
	assert_output "$ORG/stack_feat1"
}

@test "standalone: ./codespace-stack-ls -h prints stack help" {
	cd "$ORG"
	run "$REPO_ROOT/codespace-stack-ls" -h
	assert_success
	assert_output --partial "codespace stack ls"
	assert_output --partial "--integrated"
	assert_output --partial "--older-than"
}
