#!/usr/bin/env bats

# cs_post_create__link_files_from_{repo,config} on the remote
# (CS_REMOTE_CODESPACE=1): no symlinking, just verify each declared file
# is present in cwd, warn if not.

load helpers

setup() {
	common_setup

	# we need to invoke the cs_post_create__link_files_from_* helpers as the
	# 'codespace' subcommand the way real post-create scripts do — that's
	# the path that the link helpers are wired to via the CLI dispatcher.
	# (sourcing 'codespace' top-level isn't safe; it has its own 'main' flow.)
	# Easiest: run `codespace post-create.link-files-from-repo <args>`.
	export PATH="$REPO_ROOT:$PATH"

	WORKTREE="$SANDBOX/wt"
	mkdir -p "$WORKTREE"
	cd "$WORKTREE"
}

@test "remote-mode: link-files-from-repo with file present -> silent OK, no symlink" {
	echo "envcontent" > "$WORKTREE/.env"

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-repo .env
	assert_success
	[ -z "$stderr" ]

	# the file is the original, not a symlink
	[ -f "$WORKTREE/.env" ]
	[ ! -L "$WORKTREE/.env" ]
}

@test "remote-mode: link-files-from-repo with file missing -> warn on stderr" {
	# .env intentionally absent

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-repo .env
	assert_success
	[[ "$stderr" == *"warn: declared file '.env' missing from remote worktree"* ]]
	[[ "$stderr" == *"link-files-from-repo"* ]]

	# definitely no symlink was created
	[ ! -L "$WORKTREE/.env" ]
	[ ! -e "$WORKTREE/.env" ]
}

@test "remote-mode: link-files-from-config with file present -> silent OK, no symlink, no git exclude" {
	# we don't even need a git repo for this in remote mode — verify-only.
	echo "shared" > "$WORKTREE/AGENTS.md"

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-config AGENTS.md
	assert_success
	[ -z "$stderr" ]
	[ ! -L "$WORKTREE/AGENTS.md" ]
}

@test "remote-mode: link-files-from-config with file missing -> warn on stderr" {
	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-config AGENTS.md
	assert_success
	[[ "$stderr" == *"warn: declared file 'AGENTS.md' missing from remote worktree"* ]]
	[[ "$stderr" == *"link-files-from-config"* ]]
}

@test "remote-mode: multiple files, mixed presence -> single OK, single warn" {
	echo "a" > "$WORKTREE/a"
	# 'b' missing

	CS_REMOTE_CODESPACE=1 run --separate-stderr \
		codespace post-create.link-files-from-repo a b
	assert_success
	[[ "$stderr" != *"'a'"* ]]
	[[ "$stderr" == *"declared file 'b' missing"* ]]
}
