#!/usr/bin/env bats

# End-to-end create-remote-worktree flow with shimmed ssh/rsync.
# Exercises cs_create_via_remote_worktree against a REAL local git repo and
# REAL layer2 config dir. Catches integration bugs that pure unit tests miss
# (e.g. collect resolving against a non-existent stub, or the on-remote
# post-create script lacking $HOME/.local/bin on PATH).

load helpers

setup() {
	common_setup
	source_utils

	# install_ssh_shims wires shim-bin onto PATH first, so any ssh/rsync
	# invocation from the SUT gets logged. SHIM_LOG_STDIN=1 captures heredoc
	# bodies sent to ssh (the remote post-create / bootstrap script bodies).
	export SHIM_LOG_STDIN=1
	install_ssh_shims
	# avoid the editor-open at the end of the create flow
	export CS_NO_EDIT=1

	# make codespace-remote's helpers available
	# shellcheck disable=SC1090
	source "$REPO_ROOT/codespace-remote"

	# real local base repo at $HOME/projects/myrepo (so cs_repo_id derives
	# 'projects/myrepo' relative to $HOME)
	REPO="$SANDBOX/projects/myrepo"
	mkrepo "$REPO"
	echo "secret" > "$REPO/.env"

	# real layer2 config dir with post-create that declares one repo file
	# (.env) and one config file (AGENTS.md)
	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	mkdir -p "$CODESPACE_CONFIG_ROOT/projects/myrepo/.codespace"
	echo "agents" > "$CODESPACE_CONFIG_ROOT/projects/myrepo/AGENTS.md"
	cat > "$CODESPACE_CONFIG_ROOT/projects/myrepo/.codespace/post-create" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
codespace post-create.link-files-from-repo .env
codespace post-create.link-files-from-config AGENTS.md
EOF
	chmod +x "$CODESPACE_CONFIG_ROOT/projects/myrepo/.codespace/post-create"

	cd "$REPO"
}

@test "remote-create e2e: ships layer2 + repo files, post-create has PATH + CS_REMOTE_CODESPACE" {
	# stdin from /dev/null so the ssh shim's `cat` (under SHIM_LOG_STDIN=1)
	# never blocks on inherited tty/pipe for cs_ssh (no-heredoc) calls.
	run --separate-stderr cs_create_via_remote_worktree "user@host" "feat" </dev/null
	assert_success

	# the create flow announced shipping each declared file (regression for
	# the collect-resolves-against-stub bug — would be silent if manifest empty)
	[[ "$stderr" == *"==> [user@host] shipping config:AGENTS.md"* ]]
	[[ "$stderr" == *"==> [user@host] shipping repo:.env"* ]]

	# the actual rsync invocations went out for both files
	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"$REPO/.env"*"user@host:codespace/projects/myrepo_feat/.env"* ]]
	[[ "$log" == *"$CODESPACE_CONFIG_ROOT/projects/myrepo/AGENTS.md"*"user@host:codespace/projects/myrepo_feat/AGENTS.md"* ]]

	# the .codespace/ scripts mirror also went out (rsync_config_to_remote)
	[[ "$log" == *"$CODESPACE_CONFIG_ROOT/projects/myrepo/.codespace/"*"user@host:codespace-config/projects/myrepo/.codespace/"* ]]

	# the on-remote post-create script body sets PATH + CS_REMOTE_CODESPACE
	# (regression for both the missing-PATH-export bug and the skip+verify
	# wiring). isolate the block by grabbing the section after a 'codespace
	# post-create' invocation.
	[[ "$log" == *'export PATH="$HOME/.local/bin:$PATH"'* ]]
	[[ "$log" == *"export CS_REMOTE_CODESPACE=1"* ]]
	[[ "$log" == *'codespace post-create "$dest_abs"'* ]]

	# local marker was written using the new schema
	stub="$SANDBOX/projects/myrepo_feat"
	[ -f "$stub/.codespace-remote" ]
	grep -q '^relpath=codespace/projects/myrepo_feat$' "$stub/.codespace-remote"
	grep -q '^host=user@host$' "$stub/.codespace-remote"
	grep -q '^kind=worktree$' "$stub/.codespace-remote"
}
