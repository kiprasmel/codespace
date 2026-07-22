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

# Safe stack with ignored node_modules/ reclaimable via git clean -xdf.
# Optional arg: blob size in KiB (default 200). Reuses repo-a when present.
mk_cleanable_stack() {
	local branch="$1" kib="${2:-200}" stack_dir
	if [ ! -d "$ORG/repo-a/.git" ]; then
		mk_repo_with_origin repo-a
		echo 'node_modules/' >> "$ORG/repo-a/.gitignore"
		git -C "$ORG/repo-a" add .gitignore
		git -C "$ORG/repo-a" commit -q -m "ignore node_modules"
	fi
	if ! git -C "$ORG/repo-a" show-ref --verify --quiet "refs/heads/$branch"; then
		git -C "$ORG/repo-a" branch "$branch" master
		git -C "$ORG/repo-a" push -q origin "$branch"
	fi
	stack_dir="$(mk_stack "$branch" repo-a)"
	mkdir -p "$stack_dir/repo-a/node_modules"
	dd if=/dev/zero of="$stack_dir/repo-a/node_modules/blob.bin" bs=1024 count="$kib" 2>/dev/null
	git -C "$stack_dir/repo-a" branch --set-upstream-to=origin/"$branch" >/dev/null
	echo "$stack_dir"
}

# --- dry-run -----------------------------------------------------------------

@test "clean: dry-run reports reclaimable size and deletes nothing" {
	mk_cleanable_stack feat

	local blob="$ORG/stack_feat/repo-a/node_modules/blob.bin"
	assert [ -f "$blob" ]

	cd "$ORG"
	run --separate-stderr cs_stack_clean
	assert_success
	assert_output --partial "SIZE"
	assert_output --partial "feat"
	assert [ -f "$blob" ]
	[[ "$stderr" == *"total reclaimable"* ]]
	[[ "$stderr" == *"pass --apply"* ]]
}

@test "clean: --apply removes ignored files but keeps tracked files" {
	mk_cleanable_stack feat

	local blob="$ORG/stack_feat/repo-a/node_modules/blob.bin"
	local tracked="$ORG/stack_feat/repo-a/.gitignore"
	assert [ -f "$blob" ]
	assert [ -f "$tracked" ]

	cd "$ORG"
	run --separate-stderr cs_stack_clean --apply
	assert_success
	assert [ ! -f "$blob" ]
	assert [ -f "$tracked" ]
	[[ "$stderr" == *"cleaned:"* ]]
}

@test "clean: -f alias applies the clean" {
	mk_cleanable_stack feat

	local blob="$ORG/stack_feat/repo-a/node_modules/blob.bin"
	cd "$ORG"
	run cs_stack_clean -f
	assert_success
	assert [ ! -f "$blob" ]
}

# --- safety skips ------------------------------------------------------------

@test "clean: skips a stack with an untracked non-ignored file" {
	mk_cleanable_stack feat
	touch "$ORG/stack_feat/repo-a/leftover.txt"

	cd "$ORG"
	run --separate-stderr cs_stack_clean
	assert_success
	assert [ -f "$ORG/stack_feat/repo-a/node_modules/blob.bin" ]
	[[ "$stderr" == *"skip (unsafe repos)"* ]]
	[[ "$stderr" == *"nothing to clean"* ]]
}

@test "clean: skips a stack with uncommitted tracked changes" {
	mk_cleanable_stack feat
	echo dirty >> "$ORG/stack_feat/repo-a/.gitignore"

	cd "$ORG"
	run --separate-stderr cs_stack_clean
	assert_success
	assert [ -f "$ORG/stack_feat/repo-a/node_modules/blob.bin" ]
	[[ "$stderr" == *"skip (unsafe repos)"* ]]
}

@test "clean: skips a stack with unpushed commits" {
	mk_cleanable_stack feat
	git -C "$ORG/stack_feat/repo-a" commit -q --allow-empty -m "local only"

	cd "$ORG"
	run --separate-stderr cs_stack_clean
	assert_success
	assert [ -f "$ORG/stack_feat/repo-a/node_modules/blob.bin" ]
	[[ "$stderr" == *"skip (unsafe repos)"* ]]
}

# --- filters / ordering ------------------------------------------------------

@test "clean: --older-than keeps old stacks only" {
	local old_stack fresh_stack
	old_stack="$(mk_cleanable_stack old)"
	fresh_stack="$(mk_cleanable_stack fresh)"
	touch -t 202001010000 "$old_stack"

	cd "$ORG"
	run cs_stack_clean --older-than 30d --quiet
	assert_success
	assert_output --partial "$old_stack"
	refute_output --partial "$fresh_stack"
}

@test "clean: sorts largest-first and prints total" {
	mk_cleanable_stack small 50
	mk_cleanable_stack big 400

	cd "$ORG"
	run --separate-stderr cs_stack_clean
	assert_success

	local i_big=-1 i_small=-1 idx=0 line
	for line in "${lines[@]}"; do
		[[ "$line" == *big ]]   && i_big=$idx
		[[ "$line" == *small ]] && i_small=$idx
		idx=$((idx + 1))
	done
	[ "$i_big" -ge 0 ]
	[ "$i_small" -ge 0 ]
	[ "$i_big" -lt "$i_small" ]
	[[ "$stderr" == *"total reclaimable"* ]]
	[[ "$stderr" == *"2 stacks"* ]]
}

@test "clean: --quiet prints bytes<TAB>path" {
	mk_cleanable_stack feat

	cd "$ORG"
	run cs_stack_clean --quiet
	assert_success
	[[ "$output" == *$'\t'"$ORG/stack_feat" ]]
}

@test "clean: rejects unknown flags" {
	cd "$ORG"
	run --separate-stderr cs_stack_clean --bogus
	assert_failure
	[[ "$stderr" == *"unknown argument"* ]]
}
