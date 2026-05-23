#!/usr/bin/env bats

# cs_post_create__link_files_from_{repo,config}: local/remote/collect modes
# behave consistently. Materialization differs intentionally (local = symlink,
# remote = real file shipped by the create flow), but git-exclude semantics
# match local <-> remote.

load helpers

setup() {
	common_setup

	# Real git repo: we need to assert against `.git/info/exclude`, and the
	# remote-mode path of link-files-from-config calls cs_git_exclude_add
	# now (parity with local).
	WORKTREE="$SANDBOX/wt"
	mkrepo "$WORKTREE"

	# `codespace post-create.link-files-from-*` resolves to our working-tree
	# script via PATH.
	export PATH="$REPO_ROOT:$PATH"

	cd "$WORKTREE"

	EXCLUDE="$WORKTREE/.git/info/exclude"
	mkdir -p "$(dirname "$EXCLUDE")"
	: > "$EXCLUDE"
}

# --- link-files-from-config: remote-mode parity with local ---

@test "remote-mode config: file present -> silent OK + adds to .git/info/exclude (parity)" {
	echo "shared" > "$WORKTREE/AGENTS.md"

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-config AGENTS.md
	assert_success
	[ -z "$stderr" ]

	# real file (not symlink) — shipped by the create flow
	[ -f "$WORKTREE/AGENTS.md" ]
	[ ! -L "$WORKTREE/AGENTS.md" ]

	# parity: hidden from git so `git status` is clean (just like local)
	grep -qxF 'AGENTS.md' "$EXCLUDE"
}

@test "remote-mode config: file missing -> warn on stderr (and still adds to exclude)" {
	# AGENTS.md intentionally absent — declaration was made, ship failed.

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-config AGENTS.md
	assert_success
	[[ "$stderr" == *"warn: declared file 'AGENTS.md' missing from remote worktree"* ]]
	[[ "$stderr" == *"link-files-from-config"* ]]

	# git-exclude still updates: declaration is the source of truth.
	grep -qxF 'AGENTS.md' "$EXCLUDE"
}

@test "config: parity — local symlink-mode and remote verify-mode produce the same .git/info/exclude" {
	# Set up a layer2 config dir for local-mode resolution.
	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	mkdir -p "$CODESPACE_CONFIG_ROOT"
	# fake repo-id derivation: cs_config_path takes
	# realpath --relative-to=$HOME of the base repo.
	repo_id="$(realpath --relative-to="$HOME" "$WORKTREE")"
	mkdir -p "$CODESPACE_CONFIG_ROOT/$repo_id"
	echo "shared" > "$CODESPACE_CONFIG_ROOT/$repo_id/AGENTS.md"

	# 1. local mode: symlink + exclude.
	run --separate-stderr codespace post-create.link-files-from-config AGENTS.md
	assert_success
	[ -L "$WORKTREE/AGENTS.md" ]
	local_excl="$(grep -xF 'AGENTS.md' "$EXCLUDE" | wc -l | tr -d ' ')"
	[ "$local_excl" = "1" ]

	# Reset exclude + materialization for the remote run.
	rm -f "$WORKTREE/AGENTS.md"
	: > "$EXCLUDE"

	# Simulate the create flow having shipped a real file.
	echo "shared" > "$WORKTREE/AGENTS.md"

	# 2. remote mode: verify + exclude (same outcome for exclude).
	CS_REMOTE_CODESPACE=1 run --separate-stderr codespace post-create.link-files-from-config AGENTS.md
	assert_success
	[ ! -L "$WORKTREE/AGENTS.md" ]
	[ -f "$WORKTREE/AGENTS.md" ]
	remote_excl="$(grep -xF 'AGENTS.md' "$EXCLUDE" | wc -l | tr -d ' ')"
	[ "$remote_excl" = "1" ]
}

# --- link-files-from-repo: remote mode does NOT touch .git/info/exclude ---

@test "remote-mode repo: file present -> silent OK, no symlink, no exclude touch" {
	echo "envcontent" > "$WORKTREE/.env"

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-repo .env
	assert_success
	[ -z "$stderr" ]

	[ -f "$WORKTREE/.env" ]
	[ ! -L "$WORKTREE/.env" ]

	# .env is expected to be in the repo's own .gitignore. The exclude file
	# must remain untouched — that's the contract for from-repo (in BOTH
	# local and remote modes; symmetry preserved).
	[ ! -s "$EXCLUDE" ]
}

@test "remote-mode repo: file missing -> warn on stderr, no exclude touch" {
	# .env intentionally absent

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-repo .env
	assert_success
	[[ "$stderr" == *"warn: declared file '.env' missing from remote worktree"* ]]
	[[ "$stderr" == *"link-files-from-repo"* ]]

	[ ! -L "$WORKTREE/.env" ]
	[ ! -e "$WORKTREE/.env" ]
	[ ! -s "$EXCLUDE" ]
}

@test "remote-mode repo: multiple files, mixed presence -> single warn" {
	echo "a" > "$WORKTREE/a"
	# 'b' missing

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-repo a b
	assert_success
	[[ "$stderr" != *"'a'"* ]]
	[[ "$stderr" == *"declared file 'b' missing"* ]]
	[ ! -s "$EXCLUDE" ]
}
