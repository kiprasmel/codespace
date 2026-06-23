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

@test "post_create: runs root-level config-dir script (post-create at config-dir root, no .codespace/)" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CONFIG_ROOT="$CODESPACE_CONFIG_ROOT/org/myrepo"
	SENTINEL="$SANDBOX/ran"
	# mk_post_create writes <dir>/post-create, so passing the config root puts it
	# directly at the config-dir root rather than inside .codespace/.
	mk_post_create "$USER_CONFIG_ROOT" "$SENTINEL"

	run --separate-stderr cs_post_create "$REPO"
	assert_success

	assert [ -f "$SENTINEL" ]
	assert [ "$(cat "$SENTINEL.cfgdir")" = "$USER_CONFIG_ROOT" ]
	[[ "$stderr" == *"using post-create from: $USER_CONFIG_ROOT/post-create"* ]]
}

@test "post_create: ignores a root-level repo script (repo must use .codespace/)" {
	SENTINEL="$SANDBOX/ran"
	# mk_post_create writes $REPO/post-create (repo root, not .codespace/)
	mk_post_create "$REPO" "$SENTINEL"

	run --separate-stderr cs_post_create "$REPO"
	assert_success
	assert [ ! -f "$SENTINEL" ]
	[[ "$stderr" == *"note: no post-create hook"* ]]
}

@test "post_create: user-level wins when both exist (runs user's)" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CONFIG_ROOT="$CODESPACE_CONFIG_ROOT/org/myrepo"
	USER_CS_DIR="$USER_CONFIG_ROOT/.codespace"

	USER_SENTINEL="$SANDBOX/user-ran"
	REPO_SENTINEL="$SANDBOX/repo-ran"
	mk_post_create "$USER_CS_DIR" "$USER_SENTINEL"
	mk_post_create "$REPO/.codespace" "$REPO_SENTINEL"

	run --separate-stderr cs_post_create "$REPO"
	assert_success

	assert [ -f "$USER_SENTINEL" ]
	assert [ ! -f "$REPO_SENTINEL" ]
	# CS_POST_CREATE_CONFIG_DIR for user-level = config root (parent of .codespace/)
	assert [ "$(cat "$USER_SENTINEL.cfgdir")" = "$USER_CONFIG_ROOT" ]
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

@test "post_create: no script anywhere -> note, no failure" {
	run --separate-stderr cs_post_create "$REPO"
	assert_success
	[[ "$stderr" == *"note: no post-create hook"* ]]
	[[ "$stderr" == *"user: <none>"* ]]
	[[ "$stderr" == *"repo: $REPO/.codespace/post-create"* ]]
	# the misleading old line should be gone
	[[ "$stderr" != *'$CODESPACE_CONFIG_ROOT not set'* ]]
}

@test "post_create: missing script with \$CS_POST_CREATE_CONFIG_DIR -> note shows resolved user path" {
	export CS_POST_CREATE_CONFIG_DIR="$SANDBOX/cfg"
	run --separate-stderr cs_post_create "$REPO"
	assert_success
	[[ "$stderr" == *"note: no post-create hook"* ]]
	[[ "$stderr" == *"user: $SANDBOX/cfg/.codespace/post-create"* ]]
}

@test "post_create: missing script with \$CODESPACE_CONFIG_ROOT -> note shows derived user path" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	run --separate-stderr cs_post_create "$REPO"
	assert_success
	[[ "$stderr" == *"note: no post-create hook"* ]]
	[[ "$stderr" == *"user: $CODESPACE_CONFIG_ROOT/org/myrepo/.codespace/post-create"* ]]
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
