#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_ls

	ORG="$SANDBOX/org"
	REMOTES="$SANDBOX/remotes"
	mkdir -p "$ORG" "$REMOTES"

	# realpath of the org dir: cs_abs_path_base_repo canonicalizes through git
	# (/var -> /private/var on macOS), so paths cs_ls prints are canonical.
	REAL_ORG="$(realpath "$ORG")"
}

# --- fixtures ----------------------------------------------------------------

# repo at $ORG/<name> with a bare origin that has master, origin/HEAD -> master,
# and master tracking origin/master.
mk_repo_with_origin() {
	local name="$1"
	local repo="$ORG/$name"
	local remote="$REMOTES/$name.git"

	git init --bare -q "$remote"
	mkrepo "$repo"
	git -C "$repo" remote add origin "$remote"
	git -C "$repo" push -q origin master
	git -C "$repo" remote set-head origin master
	git -C "$repo" branch --set-upstream-to=origin/master master >/dev/null
}

# worktree codespace at $ORG/<repo>_<branch>. reuses an existing branch or
# creates it. args: repo branch
mk_wt_cs() {
	local repo="$1" branch="$2"
	local base="$ORG/$repo" dest="$ORG/${repo}_${branch}"
	if git -C "$base" show-ref --verify --quiet "refs/heads/$branch"; then
		git -C "$base" worktree add -q "$dest" "$branch"
	else
		git -C "$base" worktree add -q "$dest" -b "$branch"
	fi
	echo "$dest"
}

# clone codespace at $ORG/<repo>_<branch> (fresh clone + CODESPACE_IS_CLONE
# marker). args: repo branch
mk_clone_cs() {
	local repo="$1" branch="$2"
	local dest="$ORG/${repo}_${branch}"
	git clone -q "$REMOTES/$repo.git" "$dest"
	git -C "$dest" checkout -q -b "$branch"
	echo "$repo" > "$dest/.git/CODESPACE_IS_CLONE"
	echo "$dest"
}

# remote-stub codespace at $ORG/<repo>_<branch> (local .codespace-remote marker,
# no .git). args: repo branch [host]
mk_remote_stub() {
	local repo="$1" branch="$2" host="${3:-prod}"
	local dest="$ORG/${repo}_${branch}"
	mkdir -p "$dest"
	cat > "$dest/.codespace-remote" <<EOF
host=$host
relpath=codespace/org/${repo}_${branch}
kind=worktree
branch=$branch
EOF
	echo "$dest"
}

# stack at $ORG/stack_<branch> containing a worktree of each given repo.
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

# --- codespaces section ------------------------------------------------------

@test "ls: lists worktree + clone + remote codespaces of the current repo" {
	mk_repo_with_origin repo-a
	mk_wt_cs repo-a wt1
	mk_clone_cs repo-a clone1
	mk_remote_stub repo-a rem1 prod

	cd "$ORG/repo-a"
	run cs_ls
	assert_success
	assert_output --partial "codespaces in $REAL_ORG"
	assert_output --partial "KIND"
	# worktree
	assert_output --partial "worktree"
	assert_output --partial "wt1"
	# clone
	assert_output --partial "clone"
	assert_output --partial "clone1"
	# remote stub (found locally; host annotated)
	assert_output --partial "remote"
	assert_output --partial "rem1"
	assert_output --partial "@prod"
}

@test "ls: excludes the main repo and unrelated sibling repos" {
	mk_repo_with_origin repo-a
	mk_wt_cs repo-a wt1
	# a real sibling repo that matches the repo-a_* glob but isn't a codespace
	mkrepo "$ORG/repo-a_plain"
	# an entirely unrelated repo
	mk_repo_with_origin other

	cd "$ORG/repo-a"
	run cs_ls -q
	assert_success
	# only the wt1 codespace; not the main repo, repo-a_plain, or other
	assert_output "$REAL_ORG/repo-a_wt1"
}

@test "ls: runs from inside a worktree (org resolved via git common-dir)" {
	mk_repo_with_origin repo-a
	mk_wt_cs repo-a wt1

	cd "$ORG/repo-a_wt1"
	run cs_ls -q
	assert_success
	assert_output "$REAL_ORG/repo-a_wt1"
}

@test "ls: empty repo -> success, no output" {
	mk_repo_with_origin repo-a
	cd "$ORG/repo-a"
	run cs_ls
	assert_success
	assert_output ""
}

@test "ls: errors when not inside a git repo" {
	cd "$ORG"
	run --separate-stderr cs_ls
	assert_failure
	[[ "$stderr" == *"not inside a git repo"* ]]
}

# --- stacks section ----------------------------------------------------------

@test "ls: lists stacks containing this repo last, under a separate header" {
	mk_repo_with_origin repo-a
	mk_repo_with_origin repo-b
	mk_wt_cs repo-a wt1
	mk_stack big repo-a          # contains repo-a -> listed
	mk_stack nope repo-b         # no repo-a -> excluded

	cd "$ORG/repo-a"
	run cs_ls
	assert_success
	assert_output --partial "codespaces in $REAL_ORG"
	assert_output --partial "stacks in $REAL_ORG"
	assert_output --partial "big"
	refute_output --partial "nope"

	# codespaces section comes before the stacks section
	local cs_line st_line
	cs_line="$(echo "$output" | grep -n "codespaces in" | head -1 | cut -d: -f1)"
	st_line="$(echo "$output" | grep -n "stacks in" | head -1 | cut -d: -f1)"
	[ "$cs_line" -lt "$st_line" ]
}

@test "ls -q: prints codespace paths first, then stack paths" {
	mk_repo_with_origin repo-a
	mk_wt_cs repo-a wt1
	mk_stack big repo-a

	cd "$ORG/repo-a"
	run cs_ls -q
	assert_success
	assert_line --index 0 "$REAL_ORG/repo-a_wt1"
	assert_line --index 1 "$REAL_ORG/stack_big"
}

@test "ls: stacks-only repo still shows the stacks section (no codespaces header)" {
	mk_repo_with_origin repo-a
	mk_stack big repo-a

	cd "$ORG/repo-a"
	run cs_ls
	assert_success
	refute_output --partial "codespaces in"
	assert_output --partial "stacks in $REAL_ORG"
	assert_output --partial "big"
}

# --- --older-than ------------------------------------------------------------

@test "ls --older-than: keeps old, drops fresh" {
	mk_repo_with_origin repo-a
	local old fresh
	old="$(mk_wt_cs repo-a old)"
	fresh="$(mk_wt_cs repo-a fresh)"

	touch -t 202001010000 "$old"

	cd "$ORG/repo-a"
	run cs_ls --older-than 30d -q
	assert_success
	assert_output "$(realpath "$old")"
}

@test "ls --older-than: rejects bogus duration" {
	mk_repo_with_origin repo-a
	cd "$ORG/repo-a"
	run --separate-stderr cs_ls --older-than nonsense
	assert_failure
	[[ "$stderr" == *"invalid duration"* ]]
}

# --- --rm --------------------------------------------------------------------

@test "ls --rm: removes a safe codespace, skips an unsafe one" {
	mk_repo_with_origin repo-a
	# safe: feat exists on origin, upstream set, nothing dirty
	git -C "$ORG/repo-a" branch feat master
	git -C "$ORG/repo-a" push -q origin feat
	local safe unsafe
	safe="$(mk_wt_cs repo-a feat)"
	git -C "$safe" branch --set-upstream-to=origin/feat >/dev/null
	# unsafe: untracked file present
	unsafe="$(mk_wt_cs repo-a wip)"
	touch "$unsafe/leftover.txt"

	cd "$ORG/repo-a"
	run --separate-stderr cs_ls --rm
	assert_success
	assert [ ! -d "$safe" ]
	assert [ -d "$unsafe" ]
}

@test "ls --rm: removes a stack containing this repo" {
	mk_repo_with_origin repo-a
	git -C "$ORG/repo-a" branch feat master
	git -C "$ORG/repo-a" push -q origin feat
	mk_stack feat repo-a
	git -C "$ORG/stack_feat/repo-a" branch --set-upstream-to=origin/feat >/dev/null

	cd "$ORG/repo-a"
	run cs_ls --rm
	assert_success
	assert [ ! -d "$ORG/stack_feat" ]
}

# --- argument validation -----------------------------------------------------

@test "ls: rejects unknown flags" {
	mk_repo_with_origin repo-a
	cd "$ORG/repo-a"
	run --separate-stderr cs_ls --bogus
	assert_failure
	[[ "$stderr" == *"unknown argument"* ]]
}

@test "ls -h: prints ls help" {
	run cs_ls -h
	assert_success
	assert_output --partial "codespace ls"
	assert_output --partial "--older-than"
	assert_output --partial "--rm"
}

# --- standalone executable ---------------------------------------------------

@test "standalone: ./codespace-ls -q behaves like 'codespace ls -q'" {
	mk_repo_with_origin repo-a
	mk_wt_cs repo-a wt1

	cd "$ORG/repo-a"
	run "$REPO_ROOT/codespace-ls" -q
	assert_success
	assert_output "$REAL_ORG/repo-a_wt1"
}
