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
	# live-sync probes must never touch the host's real mutagen daemon (a plain
	# `codespace sync` lists sessions to reconcile commit-during-live). Tests that
	# exercise mutagen opt back in via install_mutagen_shim (which clears this).
	export CS_NO_MUTAGEN=1
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

# Same DIRNAME-rewrite trick for codespace-sync. Sourcing pulls in utils
# (+ remote) and the codespace-sync-{commit,uncommitted} siblings, giving the
# test shell cs_sync / cs_sync_decide_uncommitted / cs_sync_merge_dirty /
# cs_sync_ignored_excludes / cs_sync_marker_* etc.
source_sync() {
	local tmp
	tmp="$(mktemp)"
	sed "s|^DIRNAME=.*|DIRNAME=\"$REPO_ROOT\"|" "$REPO_ROOT/codespace-sync" > "$tmp"
	# shellcheck disable=SC1090
	CS_SYNC_NO_RUN=1 source "$tmp"
	rm -f "$tmp"
}

# codespace-dev is a flat module (no $0-based DIRNAME) but its runtime helpers
# call into codespace-utils/-remote/-stack. Source utils first (pulls in remote),
# optionally stack, then dev with its run-guard set. Gives the test shell the
# cs_dev_* helpers (url slug, port resolution, plan build, caddy regen, session).
source_dev() {
	source_utils
	# shellcheck disable=SC1090
	CS_DEV_NO_RUN=1 source "$REPO_ROOT/codespace-dev"
}

# codespace-worktree resolves DIRNAME via BASH_SOURCE, so it sources cleanly
# under bats with its run-guard set. Gives the test shell cs_worktree_create etc.
source_worktree() {
	# shellcheck disable=SC1090
	CS_WORKTREE_NO_RUN=1 source "$REPO_ROOT/codespace-worktree"
}

# --- "local remote" harness for sync e2e -------------------------------------
#
# Install ssh + rsync shims that operate on a LOCAL $REMOTE_HOME instead of a
# real host, so commit integration (which uses real local `git fetch`/`git push`
# over GIT_SSH_COMMAND) genuinely transfers history. The ssh shim runs the
# remote command locally with HOME=$REMOTE_HOME; the rsync shim rewrites a
# `host:relpath` endpoint to `$REMOTE_HOME/relpath` and delegates to real rsync.
# Prepends the shim dir to PATH. Call after common_setup.
setup_local_remote() {
	# This fake remote is a local dir reached over a stubbed ssh/rsync -- it is a
	# plain host-FS target, NOT a DinD sandbox. Provisioning now defaults to the
	# per-stack sandbox, so opt out here (the escape hatch) to exercise the
	# host-FS sync/open mechanics. Real sandbox provisioning is covered by the
	# sandbox_* suites (which mock the ensure path) and the white-monster e2e.
	export CS_SANDBOX=0

	REMOTE_HOME="$BATS_TEST_TMPDIR/remote-home"
	mkdir -p "$REMOTE_HOME"
	export REMOTE_HOME
	# the remote needs a git identity for any on-remote commit (the live
	# commit-both-ends bridge).
	cat > "$REMOTE_HOME/.gitconfig" <<-EOF
		[user]
			email = remote@example.com
			name = remote
		[init]
			defaultBranch = master
	EOF

	local lr_bin="$BATS_TEST_TMPDIR/lr-bin"
	local real_rsync
	real_rsync="$(command -v rsync)"
	mkdir -p "$lr_bin"

	{
		echo '#!/usr/bin/env bash'
		echo "REMOTE_HOME=\"$REMOTE_HOME\""
		cat <<'SSH'
args=("$@"); i=0; cmd=()
while [ $i -lt ${#args[@]} ]; do
	a="${args[$i]}"
	case "$a" in
		-o|-p) i=$((i+2)); continue ;;
		--) i=$((i+1)); cmd=("${args[@]:$i}"); break ;;
		-*) i=$((i+1)); continue ;;
		*) i=$((i+1)); cmd=("${args[@]:$i}"); break ;;
	esac
done
[ "${cmd[0]:-}" = "--" ] && cmd=("${cmd[@]:1}")
cd "$REMOTE_HOME"
HOME="$REMOTE_HOME" exec bash -c "${cmd[*]}"
SSH
	} > "$lr_bin/ssh"
	chmod +x "$lr_bin/ssh"

	{
		echo '#!/usr/bin/env bash'
		echo "REMOTE_HOME=\"$REMOTE_HOME\""
		echo "REAL_RSYNC=\"$real_rsync\""
		cat <<'RSYNC'
out=(); skip=0
for a in "$@"; do
	if [ $skip -eq 1 ]; then skip=0; continue; fi
	case "$a" in
		-e) skip=1; continue ;;
		*:*) out+=("$REMOTE_HOME/${a#*:}") ;;
		*) out+=("$a") ;;
	esac
done
exec "$REAL_RSYNC" "${out[@]}"
RSYNC
	} > "$lr_bin/rsync"
	chmod +x "$lr_bin/rsync"

	export PATH="$lr_bin:$PATH"
}

# Install a fake `mutagen` on PATH (shared by local + the harness "remote",
# which inherits PATH through the ssh shim). Backs sessions with files under
# $MUTAGEN_STATE and logs every invocation to $MUTAGEN_LOG so tests can assert
# create flags / idempotency. Call after setup_local_remote.
install_mutagen_shim() {
	MUTAGEN_BIN="$BATS_TEST_TMPDIR/mutagen-bin"
	MUTAGEN_STATE="$BATS_TEST_TMPDIR/mutagen-state"
	MUTAGEN_LOG="$BATS_TEST_TMPDIR/mutagen.log"
	mkdir -p "$MUTAGEN_BIN" "$MUTAGEN_STATE"
	: > "$MUTAGEN_LOG"
	export MUTAGEN_STATE MUTAGEN_LOG
	# opt back into mutagen: common_setup disables it for host hermeticity.
	unset CS_NO_MUTAGEN

	cat > "$MUTAGEN_BIN/mutagen" <<'MUT'
#!/usr/bin/env bash
echo "mutagen $*" >> "${MUTAGEN_LOG:-/dev/null}"
[ "$1" = sync ] || exit 0
shift; sub="${1:-}"; shift || true
# session name: --name=<x> on create, else the last bare (non-flag) arg.
name=""
for a in "$@"; do case "$a" in --name=*) name="${a#--name=}" ;; --*) ;; *) name="$a" ;; esac; done
case "$sub" in
	create) n=""; for a in "$@"; do case "$a" in --name=*) n="${a#--name=}" ;; esac; done; touch "$MUTAGEN_STATE/$n" ;;
	list) [ -f "$MUTAGEN_STATE/$name" ] || exit 1; echo "Name: $name"; echo "Status: Watching for changes" ;;
	# non-blocking stand-in for `mutagen sync monitor` so foreground watch tests
	# don't hang (the real command blocks until interrupted).
	monitor) [ -f "$MUTAGEN_STATE/$name" ] || exit 1 ;;
	terminate) rm -f "$MUTAGEN_STATE/$name" ;;
	pause|resume|flush) [ -f "$MUTAGEN_STATE/$name" ] || exit 1 ;;
esac
exit 0
MUT
	chmod +x "$MUTAGEN_BIN/mutagen"
	export PATH="$MUTAGEN_BIN:$PATH"
}

# Make the SUT treat the run as interactive: clear CS_NO_INTERACTIVE *and* the
# agent/CI auto-detect vars that codespace-utils uses to force non-interactive
# (CURSOR_AGENT / CI), so foreground behaviors are exercised deterministically.
force_interactive() {
	unset CS_NO_INTERACTIVE CURSOR_AGENT CI
}

# Path of the remote worktree dir (under $REMOTE_HOME) for a dest relpath.
remote_dir() {
	echo "$REMOTE_HOME/$1"
}

# Run git in the remote worktree (with HOME=$REMOTE_HOME). Args: dest_rel, git-args...
remote_git() {
	local dest_rel="$1"; shift
	HOME="$REMOTE_HOME" git -C "$REMOTE_HOME/$dest_rel" "$@"
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

# Write a stacks.json with arbitrary stacks/defaults content.
# Args: path, stacks_json_object (as JSON string for the "stacks" value)
# Optional env: STACKS_DEFAULTS_JSON for the "defaults" object
mk_stacks_json_ex() {
	local path="$1" stacks_obj="$2"
	local defaults_line=""
	if [ -n "${STACKS_DEFAULTS_JSON:-}" ]; then
		defaults_line=",
  \"defaults\": $STACKS_DEFAULTS_JSON"
	fi
	mkdir -p "$(dirname "$path")"
	cat > "$path" <<EOF
{
  "version": "0"$defaults_line,
  "stacks": $stacks_obj
}
EOF
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
	SSH_FAIL_FIRST_MARKER="$BATS_TEST_TMPDIR/ssh-fail-first.marker"
	mkdir -p "$SHIM_BIN"
	: > "$SHIM_LOG"
	rm -f "$SSH_FAIL_FIRST_MARKER"
	export SHIM_BIN SHIM_LOG SSH_FAIL_FIRST_MARKER

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
if [ "${SSH_FAIL_FIRST:-0}" = "1" ] && [ ! -f "${SSH_FAIL_FIRST_MARKER:-}" ]; then
	: > "$SSH_FAIL_FIRST_MARKER"
	rc=1
	unset SSH_NEXT_STDOUT
	exit "$rc"
fi
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
	GH_CALL_LOG="$BATS_TEST_TMPDIR/gh-calls.log"
	mkdir -p "$GH_BIN"
	: > "$GH_MERGED_FILE"
	: > "$GH_CALL_LOG"
	export GH_BIN GH_MERGED_FILE GH_CALL_LOG

	# the shim ignores --jq and emits the post-jq shape our caller expects:
	#   bulk           -> "<headRefName>\t<number>" lines for the slug
	#   --head <branch> -> the merged PR number (or nothing)
	# every invocation is logged to $GH_CALL_LOG (one line of args per call) so
	# tests can assert how often gh is hit.
	cat > "$GH_BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "${GH_CALL_LOG:-/dev/null}"
slug=""; head=""; want_head=0; limit=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
	case "${args[$i]}" in
		-R) slug="${args[$((i+1))]}" ;;
		--head) head="${args[$((i+1))]}"; want_head=1 ;;
		--limit) limit="${args[$((i+1))]}" ;;
	esac
done
[ -f "${GH_MERGED_FILE:-}" ] || exit 0
if [ "$want_head" = 1 ]; then
	# targeted query: find the merge regardless of bulk window.
	awk -F'\t' -v s="$slug" -v b="$head" '$1==s && $2==b {print $3; exit}' "$GH_MERGED_FILE"
else
	# bulk query: newest-first, truncated to --limit (last-appended = newest), so
	# a merge older than the window is hidden until the per-branch fallback.
	matches="$(awk -F'\t' -v s="$slug" '$1==s {printf "%s\t%s\n", $2, $3}' "$GH_MERGED_FILE")"
	[ -n "$matches" ] || exit 0
	if [ -n "$limit" ]; then printf '%s\n' "$matches" | tail -n "$limit"; else printf '%s\n' "$matches"; fi
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

# Install a fake $GIT_EDITOR for the --rm review flow and switch the SUT into
# interactive mode. The editor applies an optional sed program ($EDIT_SED) to
# the review file (e.g. to flip an action) and exits with $EDIT_EXIT (default
# 0). With no $EDIT_SED it leaves the file untouched (a "save as-is").
install_editor_shim() {
	EDITOR_BIN="$BATS_TEST_TMPDIR/editor-bin"
	mkdir -p "$EDITOR_BIN"
	cat > "$EDITOR_BIN/fake-editor" <<'ED'
#!/usr/bin/env bash
f="$1"
[ -n "${EDIT_CAPTURE:-}" ] && cp "$f" "$EDIT_CAPTURE"
if [ -n "${EDIT_SED:-}" ]; then
	sed "$EDIT_SED" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi
exit "${EDIT_EXIT:-0}"
ED
	chmod +x "$EDITOR_BIN/fake-editor"
	export GIT_EDITOR="$EDITOR_BIN/fake-editor"
	unset CS_NO_INTERACTIVE
}
