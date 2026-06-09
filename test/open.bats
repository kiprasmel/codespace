#!/usr/bin/env bats

# cs_write_open_script generation (+ git-exclude) and `codespace open` dispatch
# across a plain local dir, a remote stub, and a branch (the 'edit' alias).

load helpers

setup() {
	common_setup
	source_find

	# fake editor named 'cursor' (basename must be cursor/code/codium for the
	# remote-open branch) that logs its argv to $EDITOR_LOG.
	EDITOR_BIN="$BATS_TEST_TMPDIR/editor-bin"
	EDITOR_LOG="$BATS_TEST_TMPDIR/editor.log"
	mkdir -p "$EDITOR_BIN"
	: > "$EDITOR_LOG"
	cat > "$EDITOR_BIN/cursor" <<'ED'
#!/usr/bin/env bash
{ printf 'cursor'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$EDITOR_LOG"
ED
	chmod +x "$EDITOR_BIN/cursor"
	export PATH="$EDITOR_BIN:$PATH"
	export GUI_EDITOR=cursor EDITOR=cursor EDITOR_LOG
}

# --- cs_write_open_script ---

@test "cs_write_open_script: writes an executable ./open that runs 'codespace open'" {
	local dir="$SANDBOX/cs"
	mkdir -p "$dir"
	cs_write_open_script "$dir"

	[ -x "$dir/open" ]
	grep -qF 'exec codespace open' "$dir/open"
}

@test "cs_write_open_script: git working tree -> hides ./open via .git/info/exclude" {
	mkrepo "$SANDBOX/repo"
	cs_write_open_script "$SANDBOX/repo"

	[ -x "$SANDBOX/repo/open" ]
	grep -qxF 'open' "$SANDBOX/repo/.git/info/exclude"
}

@test "cs_write_open_script: plain (non-git) dir -> no .git side effects" {
	local dir="$SANDBOX/stub"
	mkdir -p "$dir"
	cs_write_open_script "$dir"

	[ -x "$dir/open" ]
	[ ! -e "$dir/.git" ]
}

# --- cs_open dispatch ---

@test "cs_open <dir>: opens a plain local codespace dir in the editor" {
	local dir="$SANDBOX/org/repo_feat"
	mkdir -p "$dir"
	# cs_open canonicalizes via cs_abspath (realpath), so compare likewise.
	local abs
	abs="$(cs_abspath "$dir")"

	run cs_open "$dir"
	assert_success

	grep -qF -- "--new-window $abs" "$EDITOR_LOG"
}

@test "cs_open (no arg): opens the codespace at the current dir" {
	local dir="$SANDBOX/org/repo_here"
	mkdir -p "$dir"
	cd "$dir"

	run cs_open
	assert_success

	grep -qF -- "--new-window $dir" "$EDITOR_LOG"
}

@test "cs_open <remote-stub>: opens over ssh-remote at the resolved remote path" {
	install_ssh_shims

	local stub="$SANDBOX/org/repo_feat"
	mkdir -p "$stub"
	cs_remote_marker_write "$stub" \
		"host=myhost" \
		"relpath=codespace/org/repo_feat" \
		"kind=worktree" \
		"branch=feat"

	# cs_remote_home resolves remote $HOME via one ssh round-trip.
	export SSH_NEXT_STDOUT="/home/remoteuser"

	run cs_open "$stub"
	assert_success

	grep -qF -- "--remote ssh-remote+myhost /home/remoteuser/codespace/org/repo_feat" "$EDITOR_LOG"
}

@test "cs_open <branch>: resolves via find and opens (edit alias)" {
	mkdir -p "$SANDBOX/org/repo_feat"
	cd "$SANDBOX/org"

	run cs_open feat
	assert_success

	grep -qF -- "--new-window $SANDBOX/org/repo_feat" "$EDITOR_LOG"
}
