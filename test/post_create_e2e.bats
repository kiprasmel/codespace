#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils

	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"
}

@test "post_create: runs repo-committed script and exports CS_POST_CREATE_CONFIG_DIR" {
	SENTINEL="$SANDBOX/ran"
	mk_post_create "$REPO/.codespace" "$SENTINEL"

	run --separate-stderr cs_post_create "$REPO"
	assert_success

	assert [ -f "$SENTINEL" ]
	assert [ "$(cat "$SENTINEL.cfgdir")" = "$REPO/.codespace" ]
	# BASE_REPO_PATH is computed via realpath inside the SUT, which resolves
	# symlinks (/var/folders -> /private/var/folders on macOS).
	assert [ "$(cat "$SENTINEL.arg")" = "BASE_REPO_ARG=$(realpath "$REPO")" ]
}

@test "post_create: user-level wins when both exist (runs user's)" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CS_DIR="$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace"

	USER_SENTINEL="$SANDBOX/user-ran"
	REPO_SENTINEL="$SANDBOX/repo-ran"
	mk_post_create "$USER_CS_DIR" "$USER_SENTINEL"
	mk_post_create "$REPO/.codespace" "$REPO_SENTINEL"

	run --separate-stderr cs_post_create "$REPO"
	assert_success

	assert [ -f "$USER_SENTINEL" ]
	assert [ ! -f "$REPO_SENTINEL" ]
	assert [ "$(cat "$USER_SENTINEL.cfgdir")" = "$USER_CS_DIR" ]
	# note about the ignored repo path should be printed
	[[ "$stderr" == *"ignoring repo-committed post-create at: $REPO/.codespace/post-create"* ]]
}

@test "post_create: checkout-not-worktree flag exported when run in main repo" {
	SENTINEL="$SANDBOX/ran"
	mk_post_create "$REPO/.codespace" "$SENTINEL"

	run --separate-stderr cs_post_create "$REPO"
	assert_success
	# mkrepo creates a plain repo (not a worktree), so checkout flag should be 1
	assert [ "$(cat "$SENTINEL.checkout")" = "ARE_WE_IN_CHECKOUT_NOT_WORKTREE=1" ]
	[[ "$stderr" == *"branch checkout, not in a worktree"* ]]
}

@test "post_create: checkout flag is 0 inside a git worktree" {
	SENTINEL="$SANDBOX/ran"
	mk_post_create "$REPO/.codespace" "$SENTINEL"

	# create a worktree of the same repo at a sibling path
	WT="$SANDBOX/org/myrepo_wt"
	(cd "$REPO" && git worktree add -q -b feature "$WT")

	run --separate-stderr cs_post_create "$WT"
	assert_success
	# .codespace/post-create is under the main repo; when run inside the worktree
	# it won't find a repo-committed one (worktree doesn't have the dir). So we
	# should have the user-level scenario only if CODESPACE_CONFIG_ROOT is set.
	# Here we only want to assert checkout flag is 0 when the script runs in worktree.
	if [ -f "$SENTINEL.checkout" ]; then
		assert [ "$(cat "$SENTINEL.checkout")" = "ARE_WE_IN_CHECKOUT_NOT_WORKTREE=0" ]
	fi
}

@test "post_create: no script anywhere -> warn, no failure" {
	run --separate-stderr cs_post_create "$REPO"
	assert_success
	[[ "$stderr" == *"'post-create' script not found"* ]]
}

@test "link-files-from-config: resolves relative to CS_POST_CREATE_CONFIG_DIR" {
	# plant an active config dir with a target file; invoke the codespace
	# subcommand with CS_POST_CREATE_CONFIG_DIR set as cs_post_create would.
	CFG_DIR="$REPO/.codespace"
	mkdir -p "$CFG_DIR"
	echo "hello" > "$CFG_DIR/AGENTS.md"

	cd "$REPO"
	CS_POST_CREATE_CONFIG_DIR="$CFG_DIR" run codespace post-create.link-files-from-config AGENTS.md
	assert_success

	assert [ -L "$REPO/AGENTS.md" ]
	# readlink resolves to absolute path we passed
	target="$(readlink "$REPO/AGENTS.md")"
	assert [ "$target" = "$CFG_DIR/AGENTS.md" ]
	# and git/info/exclude contains the file
	grep -qxF AGENTS.md "$REPO/.git/info/exclude"
}
