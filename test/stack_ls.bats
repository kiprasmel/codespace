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

# like mk_repo_with_origin, but point origin at a github.com slug so the
# gh-backed integration path engages. refs stay local (nothing is pushed to
# github); slug is test-org/<name>.
mk_repo_with_gh_origin() {
	mk_repo_with_origin "$1"
	git -C "$ORG/$1" remote set-url origin "git@github.com:test-org/$1.git"
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
	# org header printed once, then aligned columns
	assert_output --partial "in $ORG"
	assert_output --partial "AGE  BRANCH"
	assert_output --partial "feat1"
	assert_output --partial "feat2"
	# no full paths in default output (only in --quiet)
	refute_output --partial "$ORG/stack_feat1"
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
	assert_output --partial "AGE   INT  BRANCH"
	assert_output --partial "1/1  feat"
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

# --- --integrated (gh-backed) -----------------------------------------------
# the three tests above run with CS_NO_GH=1 (common_setup) and local remotes,
# so they exercise the offline ancestor/empty fallback. the tests below opt in
# to the gh path via install_gh_shim.

@test "ls --integrated: detects a squash-merged branch via gh" {
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	# branch carries work that is NOT an ancestor of master (squash-merge shape)
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "feature work"
	gh_mark_merged test-org/core feat 501

	cd "$ORG"
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "1/1  feat"
	# per-repo breakdown surfaces the merged PR number
	assert_output --partial "merged #501"
}

@test "ls --integrated: a repo with no commits beyond base counts as integrated (tag-along)" {
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_repo_with_gh_origin web
	mk_stack feat core web
	# only core has work + a merged PR; web is a tag-along with no commits
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "feature work"
	gh_mark_merged test-org/core feat 7

	cd "$ORG"
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "2/2  feat"
	assert_output --partial "merged #7"
	assert_output --partial "empty"
}

@test "ls --integrated: drops a stack whose branch has no merged PR (open)" {
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "wip"
	# no gh_mark_merged -> branch is open -> stack excluded

	cd "$ORG"
	run cs_stack_ls --integrated --quiet
	assert_success
	assert_output ""
}

@test "ls --integrated: CS_NO_GH falls back to the local ancestor check (misses squash)" {
	mk_repo_with_gh_origin core
	mk_stack feat core
	# squash-merge shape: branch has work that never became an ancestor.
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "squashed work"

	cd "$ORG"
	# CS_NO_GH=1 (from common_setup) -> gh is not consulted, so the squash-merge
	# is invisible and the stack is (conservatively) not integrated.
	run cs_stack_ls --integrated --quiet
	assert_success
	assert_output ""
}

@test "ls --integrated: --no-gh skips gh even when it would detect the merge" {
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	# squash-merge shape: work that never became an ancestor, but gh knows it merged
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "squashed work"
	gh_mark_merged test-org/core feat 99

	cd "$ORG"
	# sanity: with gh, the squash-merge is detected -> kept
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "1/1  feat"
	assert_output --partial "merged #99"

	# --no-gh forces the local-only path -> squash-merge invisible -> dropped
	run cs_stack_ls --integrated --no-gh --quiet
	assert_success
	assert_output ""
}

@test "ls --integrated: offline remote-gone heuristic detects a deleted merged branch" {
	# non-github origin -> the offline path runs even without --no-gh.
	mk_repo_with_origin core
	mk_stack feat core
	# divergent work that was pushed, then the branch was deleted on the remote
	# (typical of a merge + auto-delete).
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m work
	git -C "$ORG/stack_feat/core" push -q origin feat
	git -C "$ORG/stack_feat/core" branch --set-upstream-to=origin/feat >/dev/null
	git -C "$ORG/stack_feat/core" push -q origin --delete feat

	cd "$ORG"
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "1/1  feat"
	assert_output --partial "remote-gone"
}

# --- persistent merged-PR cache ---------------------------------------------

@test "ls --integrated: caches a merged PR and resolves it without gh next time" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"   # gives the cache a home
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "squashed work"
	gh_mark_merged test-org/core feat 77

	cd "$ORG"
	# first run resolves via gh and writes the cache
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "merged #77"
	assert [ -f "$(gh_cache_file)" ]
	run cat "$(gh_cache_file)"
	assert_output --partial "test-org/core	feat	77"

	# gh now reports nothing; without the cache the branch would look open. the
	# stack-level cache short-circuits the re-check (detail reads "cached"), so
	# the stack stays integrated with no gh query.
	: > "$GH_MERGED_FILE"
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "1/1  feat"
	assert_output --partial "cached"
}

@test "ls --integrated: --no-cache ignores the cache and re-queries gh" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"   # gives the cache a home
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "squashed work"
	gh_mark_merged test-org/core feat 77

	cd "$ORG"
	run cs_stack_ls --integrated --quiet   # populate the cache
	assert_success

	# drop the merge from gh's view; --no-cache must re-query (and miss) rather
	# than trust the cached positive -> stack now looks open -> dropped.
	: > "$GH_MERGED_FILE"
	run cs_stack_ls --integrated --no-cache --quiet
	assert_success
	assert_output ""
}

@test "ls --integrated: open branches are not cached (re-checked until merged)" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"   # gives the cache a home
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "wip"
	# not merged yet

	cd "$ORG"
	run cs_stack_ls --integrated --quiet
	assert_success
	assert_output ""                       # open -> dropped, nothing cached
	assert [ ! -f "$(gh_cache_file)" ]

	# it merges later; the (uncached) negative must be re-checked -> now kept.
	gh_mark_merged test-org/core feat 88
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "merged #88"
}

@test "ls --integrated: open stacks cost one bulk gh query per slug, not per stack" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"   # gives the cache a home
	install_gh_shim
	mk_repo_with_gh_origin core

	# three open stacks on the same slug (none marked merged)
	local b
	for b in wip1 wip2 wip3; do
		mk_stack "$b" core
		git -C "$ORG/stack_$b/core" commit -q --allow-empty -m "wip"
	done

	cd "$ORG"
	run cs_stack_ls --integrated --quiet
	assert_success
	assert_output ""                                 # all open -> dropped

	# exactly one bulk merged-PR query for the slug, and no per-branch (--head)
	# fallback queries (those used to fire once per open stack on every run).
	run grep -c -- "--head" "$GH_CALL_LOG"
	assert_output "0"
	run grep -c -- "pr list" "$GH_CALL_LOG"
	assert_output "1"
}

# --- stack-level integrated cache ------------------------------------------

@test "ls --integrated: stack-level cache short-circuits a re-check with no gh calls" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"   # gives the cache a home
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "work"
	gh_mark_merged test-org/core feat 12

	cd "$ORG"
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "1/1  feat"

	# second run: stack state unchanged -> cached verdict reused, gh untouched.
	: > "$GH_CALL_LOG"
	run cs_stack_ls --integrated --quiet
	assert_success
	assert_output "$ORG/stack_feat"
	run cat "$GH_CALL_LOG"
	assert_output ""
}

@test "ls --integrated: a new commit invalidates the stack cache (re-checks)" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m work
	gh_mark_merged test-org/core feat 5

	cd "$ORG"
	run cs_stack_ls --integrated --quiet            # caches the integrated verdict
	assert_success

	# advancing the branch changes its state hash -> cache miss -> recompute
	# (detail shows the resolved PR again, not the "cached" short-circuit).
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m more
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "merged #5"
	refute_output --partial "cached"
}

@test "ls --integrated: --no-cache ignores the stack-level cache" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m work
	gh_mark_merged test-org/core feat 7

	cd "$ORG"
	run cs_stack_ls --integrated --quiet            # would populate the cache
	assert_success

	# --no-cache forces a full recompute (detail resolves the PR, not "cached").
	run cs_stack_ls --integrated --no-cache
	assert_success
	assert_output --partial "merged #7"
	refute_output --partial "cached"
}

# --- beyond-the-window detection + TTL negative cache ----------------------

@test "ls --integrated: recovers a merge beyond the bulk window via a targeted query" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	export CS_GH_PR_LIMIT=1                          # tiny window -> easy to overflow
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m work
	gh_mark_merged test-org/core feat 42            # the target (older merge)
	gh_mark_merged test-org/core decoy 99           # newer; fills the 1-entry window

	cd "$ORG"
	run cs_stack_ls --integrated
	assert_success
	assert_output --partial "1/1  feat"
	assert_output --partial "merged #42"
	run grep -c -- "--head" "$GH_CALL_LOG"          # targeted fallback fired
	refute_output "0"
}

@test "ls --integrated: open branch in a deep repo is TTL-suppressed on repeat runs" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	export CS_GH_PR_LIMIT=1
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m work
	gh_mark_merged test-org/core decoy 99           # fills the window; feat is open

	cd "$ORG"
	run cs_stack_ls --integrated --quiet
	assert_success
	assert_output ""                                # feat open -> dropped
	run grep -c -- "--head" "$GH_CALL_LOG"
	assert_output "1"                               # one targeted query for feat

	# second run within TTL: the fresh "open" negative suppresses the re-query.
	run cs_stack_ls --integrated --quiet
	assert_success
	run grep -c -- "--head" "$GH_CALL_LOG"
	assert_output "1"
}

@test "cs_gh_pr_limit: adapts the per-repo window to the batch size" {
	unset CS_GH_PR_LIMIT
	run cs_gh_pr_limit 1;  assert_output "1000"   # one repo -> go deep (capped)
	run cs_gh_pr_limit 2;  assert_output "1000"
	run cs_gh_pr_limit 5;  assert_output "400"    # 2000/5
	run cs_gh_pr_limit 25; assert_output "100"    # many repos -> floor (one page)
	run cs_gh_pr_limit;    assert_output "1000"   # default nslugs=1
}

@test "cs_gh_pr_limit: an explicit CS_GH_PR_LIMIT pins a fixed window" {
	export CS_GH_PR_LIMIT=750
	run cs_gh_pr_limit 1;  assert_output "750"
	run cs_gh_pr_limit 25; assert_output "750"
}

# --- parallelism ------------------------------------------------------------

@test "ls --integrated: output is identical for serial and parallel job counts" {
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_repo_with_gh_origin web
	local b
	for b in alpha bravo charlie delta; do
		mk_stack "$b" core web
		git -C "$ORG/stack_$b/core" commit -q --allow-empty -m "w"
		gh_mark_merged test-org/core "$b" 1
		gh_mark_merged test-org/web  "$b" 2
	done

	# compare --quiet (paths only) so the ordering check is not perturbed by the
	# time-sensitive AGE column between the two runs.
	cd "$ORG"
	export CS_STACK_LS_JOBS=1
	run cs_stack_ls --integrated --quiet
	assert_success
	local serial="$output"
	export CS_STACK_LS_JOBS=8
	run cs_stack_ls --integrated --quiet
	assert_success
	[ "$output" = "$serial" ]
	# all four stacks resolved as integrated
	[ "$(printf '%s\n' "$output" | grep -c .)" -eq 4 ]
}

# --- --size -----------------------------------------------------------------

@test "ls --size: shows a SIZE column and sorts each org largest-first" {
	mk_repo_with_origin repo-a
	mk_stack small repo-a
	mk_stack big repo-a
	# make 'big' clearly larger than 'small'
	dd if=/dev/zero of="$ORG/stack_big/repo-a/blob.bin" bs=1024 count=300 2>/dev/null

	cd "$ORG"
	# --separate-stderr so progress notes don't land in $lines (we index rows)
	run --separate-stderr cs_stack_ls --size
	assert_success
	assert_output --partial "SIZE"
	assert_output --partial "BRANCH"

	# 'big' must be listed before 'small' (descending size)
	local i_big=-1 i_small=-1 idx=0 line
	for line in "${lines[@]}"; do
		[[ "$line" == *big ]]   && i_big=$idx
		[[ "$line" == *small ]] && i_small=$idx
		idx=$((idx + 1))
	done
	[ "$i_big" -ge 0 ]
	[ "$i_small" -ge 0 ]
	[ "$i_big" -lt "$i_small" ]
}

@test "ls --size: composes with --integrated (SIZE + INT columns)" {
	install_gh_shim
	mk_repo_with_gh_origin core
	mk_stack feat core
	git -C "$ORG/stack_feat/core" commit -q --allow-empty -m "feature work"
	gh_mark_merged test-org/core feat 12

	cd "$ORG"
	run cs_stack_ls --integrated --size
	assert_success
	assert_output --partial "INT"
	assert_output --partial "SIZE"
	assert_output --partial "merged #12"
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

# --- --rm interactive review file (git-rebase-todo style) -------------------

# integrated+safe stack `feat` (feat==master, pushed, upstream set) plus a
# divergent+safe stack `wip` (one extra commit, pushed, upstream set).
mk_rm_review_fixture() {
	mk_repo_with_origin repo-a

	git -C "$ORG/repo-a" branch feat master
	git -C "$ORG/repo-a" push -q origin feat
	mk_stack feat repo-a
	git -C "$ORG/stack_feat/repo-a" branch --set-upstream-to=origin/feat >/dev/null

	mk_stack wip repo-a
	git -C "$ORG/stack_wip/repo-a" commit -q --allow-empty -m "wip"
	git -C "$ORG/stack_wip/repo-a" push -q origin wip
	git -C "$ORG/stack_wip/repo-a" branch --set-upstream-to=origin/wip >/dev/null
}

@test "ls --rm: interactive editor defaults remove integrated, keep divergent" {
	mk_rm_review_fixture
	install_editor_shim   # save as-is

	cd "$ORG"
	run cs_stack_ls --rm
	assert_success
	assert [ ! -d "$ORG/stack_feat" ]   # integrated -> rm
	assert [ -d "$ORG/stack_wip" ]      # divergent  -> keep
}

@test "ls --rm: editing rm->keep spares an integrated stack" {
	mk_rm_review_fixture
	install_editor_shim
	export EDIT_SED='/stack_feat/ s/^rm/keep/'

	cd "$ORG"
	run cs_stack_ls --rm
	assert_success
	assert [ -d "$ORG/stack_feat" ]     # spared by the edit
	assert [ -d "$ORG/stack_wip" ]
}

@test "ls --rm: editing keep->rm removes a divergent stack" {
	mk_rm_review_fixture
	install_editor_shim
	export EDIT_SED='/stack_wip/ s/^keep/rm/'

	cd "$ORG"
	run cs_stack_ls --rm
	assert_success
	assert [ ! -d "$ORG/stack_feat" ]   # integrated default rm
	assert [ ! -d "$ORG/stack_wip" ]    # promoted to rm by the edit
}

@test "ls --rm: a non-zero editor exit aborts without removing anything" {
	mk_rm_review_fixture
	install_editor_shim
	export EDIT_EXIT=1

	cd "$ORG"
	run --separate-stderr cs_stack_ls --rm
	assert_success
	assert [ -d "$ORG/stack_feat" ]
	assert [ -d "$ORG/stack_wip" ]
	[[ "$stderr" == *"aborted"* ]]
}

@test "ls --rm: review lists rm before keep, aligned, with instructions at the bottom" {
	mk_repo_with_origin repo-a

	# integrated (branch == master, no commits beyond base) -> defaults to rm
	git -C "$ORG/repo-a" branch a master
	git -C "$ORG/repo-a" push -q origin a
	mk_stack a repo-a
	git -C "$ORG/stack_a/repo-a" branch --set-upstream-to=origin/a >/dev/null

	# divergent, long stack-dir name -> defaults to keep, widest path
	mk_stack longbranchname repo-a
	git -C "$ORG/stack_longbranchname/repo-a" commit -q --allow-empty -m wip
	git -C "$ORG/stack_longbranchname/repo-a" push -q origin longbranchname
	git -C "$ORG/stack_longbranchname/repo-a" branch --set-upstream-to=origin/longbranchname >/dev/null

	install_editor_shim
	export EDIT_CAPTURE="$BATS_TEST_TMPDIR/review.txt"
	export EDIT_EXIT=1   # capture the file, then abort (remove nothing)

	cd "$ORG"
	run cs_stack_ls --rm
	assert_success
	assert [ -f "$EDIT_CAPTURE" ]

	# first line is the integrated stack, marked rm
	run head -n 1 "$EDIT_CAPTURE"
	assert_output --partial "rm "
	assert_output --partial "stack_a"

	# ordering: rm before keep before the instruction comments (footer)
	local rm_ln keep_ln cmt_ln
	rm_ln=$(grep -n '^rm '    "$EDIT_CAPTURE" | head -1 | cut -d: -f1)
	keep_ln=$(grep -n '^keep ' "$EDIT_CAPTURE" | head -1 | cut -d: -f1)
	cmt_ln=$(grep -n '^#'     "$EDIT_CAPTURE" | head -1 | cut -d: -f1)
	[ "$rm_ln" -lt "$keep_ln" ]
	[ "$keep_ln" -lt "$cmt_ln" ]

	# the info comment column is aligned: '#' at the same offset on both entries
	local rm_hash keep_hash
	rm_hash=$(awk '/^rm /   {print index($0,"#"); exit}' "$EDIT_CAPTURE")
	keep_hash=$(awk '/^keep / {print index($0,"#"); exit}' "$EDIT_CAPTURE")
	[ "$rm_hash" -gt 0 ]
	[ "$rm_hash" = "$keep_hash" ]
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
