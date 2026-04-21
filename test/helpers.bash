#!/usr/bin/env bash

# Shared test helpers. Loaded by each .bats file via:
#   load helpers

bats_require_minimum_version 1.5.0

# --- locate repo root (REPO_ROOT is set by test/run.sh; fall back for editor runs)
if [ -z "${REPO_ROOT:-}" ]; then
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export REPO_ROOT
fi

# --- load bats-support and bats-assert (vendored)
load "$REPO_ROOT/test/vendor/bats-support/load"
load "$REPO_ROOT/test/vendor/bats-assert/load"

# --- per-test sandbox (call from each test file's setup())

common_setup() {
	# isolated sandbox with a private HOME so realpath --relative-to="$HOME"
	# computations in the SUT are deterministic.
	SANDBOX="$BATS_TEST_TMPDIR/sandbox"
	mkdir -p "$SANDBOX"
	export HOME="$SANDBOX"
	cd "$SANDBOX"

	# ensure no interactive prompts in any SUT
	export CS_NO_INTERACTIVE=1
	# avoid network fetches when SUT touches git
	export CS_NO_FETCH=1
	# don't leak env from the host
	unset CODESPACE_CONFIG_ROOT
}

# --- source library functions into the current shell

# codespace-utils can be sourced directly.
source_utils() {
	# shellcheck disable=SC1090
	source "$REPO_ROOT/codespace-utils"
}

# codespace-stack uses $0-based DIRNAME which breaks when sourced from bats
# (where $0 is the bats runner). Rewrite that one line in a tmp copy so it
# finds codespace-utils regardless of how it was sourced.
source_stack() {
	local tmp
	tmp="$(mktemp)"
	sed "s|^DIRNAME=.*|DIRNAME=\"$REPO_ROOT\"|" "$REPO_ROOT/codespace-stack" > "$tmp"
	# shellcheck disable=SC1090
	CS_STACK_NO_RUN=1 source "$tmp"
	rm -f "$tmp"
}

# --- git repo fixture

# Create a minimal git repo at the given path with one empty commit on master.
mkrepo() {
	local path="$1"
	mkdir -p "$path"
	(
		cd "$path"
		git init -q -b master
		git config user.email test@example.com
		git config user.name test
		git commit --allow-empty -q -m init
	)
}

# Write a post-create script at <dir>/post-create that `touch`es <sentinel>
# and records $CS_POST_CREATE_CONFIG_DIR to <sentinel>.cfgdir.
# Args: dir, sentinel
mk_post_create() {
	local dir="$1" sentinel="$2"
	mkdir -p "$dir"
	cat > "$dir/post-create" <<EOF
#!/usr/bin/env bash
set -eu
touch "$sentinel"
echo "\${CS_POST_CREATE_CONFIG_DIR:-}" > "$sentinel.cfgdir"
echo "ARE_WE_IN_CHECKOUT_NOT_WORKTREE=\${ARE_WE_IN_CHECKOUT_NOT_WORKTREE:-0}" > "$sentinel.checkout"
echo "BASE_REPO_ARG=\$1" > "$sentinel.arg"
EOF
	chmod +x "$dir/post-create"
}

# Write a bare stacks.json with a "default" stack (repos array).
# Args: path, [repos_json_array]
mk_stacks_json() {
	local path="$1"
	local repos="${2:-[\"repo-a\"]}"
	mkdir -p "$(dirname "$path")"
	cat > "$path" <<EOF
{
  "version": "0",
  "stacks": { "default": $repos }
}
EOF
}
