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
	# integration detection consults gh by default; keep tests offline+deterministic.
	# gh-backed tests opt in via install_gh_shim (which clears this).
	export CS_NO_GH=1
	# don't leak env from the host
	unset CODESPACE_CONFIG_ROOT
}

# Path to the persistent gh merged-PR cache for the current test (lives under
# $CODESPACE_CONFIG_ROOT/.cache; tests that exercise the cache set that var).
gh_cache_file() {
	echo "$CODESPACE_CONFIG_ROOT/.cache/gh-merged.tsv"
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

# Same DIRNAME-rewrite trick for codespace-ls (sources codespace-stack-ls etc.
# via $DIRNAME). Gives the test shell cs_ls + every helper it reuses.
source_ls() {
	local tmp
	tmp="$(mktemp)"
	sed "s|^DIRNAME=.*|DIRNAME=\"$REPO_ROOT\"|" "$REPO_ROOT/codespace-ls" > "$tmp"
	# shellcheck disable=SC1090
	CS_LS_NO_RUN=1 source "$tmp"
	rm -f "$tmp"
}

# codespace-find computes DIRNAME from $0 (breaks when sourced from bats).
# Rewrite that line; sourcing pulls in utils (+ remote) and stack transitively,
# giving the test shell cs_find / cs_edit / cs_open / cs_open_path.
source_find() {
	local tmp
	tmp="$(mktemp)"
	sed "s|^DIRNAME=.*|DIRNAME=\"$REPO_ROOT\"|" "$REPO_ROOT/codespace-find" > "$tmp"
	# shellcheck disable=SC1090
	CS_FIND_NO_RUN=1 source "$tmp"
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

# Install ssh/rsync shims into a SHIM_BIN dir on PATH that log invocations to
# $SHIM_LOG. Each shim returns the contents of $SHIM_NEXT_STDOUT (if any) and
# the exit code in $SHIM_NEXT_RC (default 0).
#
# Per-tool overrides (set BEFORE the call you want to shape):
#   SSH_NEXT_STDOUT, SSH_NEXT_RC      -- for the next ssh invocation
#   RSYNC_NEXT_STDOUT, RSYNC_NEXT_RC  -- for the next rsync invocation
#
# The shim strips the override after use so subsequent calls go back to defaults.
install_ssh_shims() {
	SHIM_BIN="$BATS_TEST_TMPDIR/shim-bin"
	SHIM_LOG="$BATS_TEST_TMPDIR/shim.log"
	mkdir -p "$SHIM_BIN"
	: > "$SHIM_LOG"
	export SHIM_BIN SHIM_LOG

	cat > "$SHIM_BIN/ssh" <<'SSH'
#!/usr/bin/env bash
# log: tool, then each arg quoted. If SHIM_LOG_STDIN=1, also drain+log stdin
# (only safe when the call site is known to feed a heredoc — otherwise `cat`
# can block on an inherited tty/pipe).
{
	printf 'ssh'
	for a in "$@"; do printf ' %q' "$a"; done
	if [ "${SHIM_LOG_STDIN:-0}" = "1" ]; then
		printf '\nSTDIN<<\n'
		cat
		printf '\n>>STDIN'
	fi
	printf '\n'
} >> "$SHIM_LOG"
if [ -n "${SSH_NEXT_STDOUT:-}" ]; then
	printf '%s' "$SSH_NEXT_STDOUT"
	unset SSH_NEXT_STDOUT
fi
rc="${SSH_NEXT_RC:-0}"
unset SSH_NEXT_RC
exit "$rc"
SSH
	chmod +x "$SHIM_BIN/ssh"

	cat > "$SHIM_BIN/rsync" <<'RSYNC'
#!/usr/bin/env bash
{
	printf 'rsync'
	for a in "$@"; do printf ' %q' "$a"; done
	printf '\n'
} >> "$SHIM_LOG"
if [ -n "${RSYNC_NEXT_STDOUT:-}" ]; then
	printf '%s' "$RSYNC_NEXT_STDOUT"
	unset RSYNC_NEXT_STDOUT
fi
rc="${RSYNC_NEXT_RC:-0}"
unset RSYNC_NEXT_RC
exit "$rc"
RSYNC
	chmod +x "$SHIM_BIN/rsync"

	# put shims first on PATH so cs_ssh / cs_rsync_to_remote pick them up
	export PATH="$SHIM_BIN:$PATH"
}

# Install a fake `gh` on PATH that answers `gh pr list` from a TSV of merged
# PRs ($GH_MERGED_FILE), each line "<slug>\t<headRefName>\t<number>". Mark a
# merged PR with gh_mark_merged <slug> <branch> <number>. Clears CS_NO_GH so
# the SUT exercises the gh-backed integration path.
install_gh_shim() {
	GH_BIN="$BATS_TEST_TMPDIR/gh-bin"
	GH_MERGED_FILE="$BATS_TEST_TMPDIR/gh-merged.tsv"
	mkdir -p "$GH_BIN"
	: > "$GH_MERGED_FILE"
	export GH_BIN GH_MERGED_FILE

	# the shim ignores --jq and emits the post-jq shape our caller expects:
	#   bulk           -> "<headRefName>\t<number>" lines for the slug
	#   --head <branch> -> the merged PR number (or nothing)
	cat > "$GH_BIN/gh" <<'GH'
#!/usr/bin/env bash
slug=""; head=""; want_head=0
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
	case "${args[$i]}" in
		-R) slug="${args[$((i+1))]}" ;;
		--head) head="${args[$((i+1))]}"; want_head=1 ;;
	esac
done
[ -f "${GH_MERGED_FILE:-}" ] || exit 0
if [ "$want_head" = 1 ]; then
	awk -F'\t' -v s="$slug" -v b="$head" '$1==s && $2==b {print $3; exit}' "$GH_MERGED_FILE"
else
	awk -F'\t' -v s="$slug" '$1==s {printf "%s\t%s\n", $2, $3}' "$GH_MERGED_FILE"
fi
GH
	chmod +x "$GH_BIN/gh"
	export PATH="$GH_BIN:$PATH"
	export CS_NO_GH=""
}

# Record a merged PR for the gh shim. Args: slug, branch, number
gh_mark_merged() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$GH_MERGED_FILE"
}
