#!/usr/bin/env bats

# cs_rsync_config_to_remote — mirrors only the .codespace/ subdir of the user's
# layer2 config dir to the remote (scripts-only; data files travel
# per-declaration via the collect+ship flow).

load helpers

setup() {
	common_setup
	source_utils
	install_ssh_shims

	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	REPO_ID="myorg/myrepo"
	CFG_ROOT="$CODESPACE_CONFIG_ROOT/$REPO_ID"
	mkdir -p "$CFG_ROOT/.codespace"
	echo '#!/bin/bash' > "$CFG_ROOT/.codespace/post-create"
	echo "secret" > "$CFG_ROOT/.env"
	echo "agents" > "$CFG_ROOT/AGENTS.md"
}

@test "rsync_config_to_remote: prints remote_rel and rsyncs only .codespace/" {
	run cs_rsync_config_to_remote "user@host" "$REPO_ID"
	assert_success
	# stdout: remote relpath of the config dir
	assert_output --partial "codespace-config/$REPO_ID"

	log="$(cat "$SHIM_LOG")"
	# the rsync source is the .codespace/ subdir, not the parent
	[[ "$log" == *"rsync"* ]]
	[[ "$log" == *"$CFG_ROOT/.codespace/"* ]]
	[[ "$log" == *"codespace-config/$REPO_ID/.codespace/"* ]]
}

@test "rsync_config_to_remote: skips data files outside .codespace/" {
	cs_rsync_config_to_remote "user@host" "$REPO_ID" >/dev/null

	log="$(cat "$SHIM_LOG")"
	# the OLD behaviour rsynced the whole layer2 dir; the new one must not
	# pass the parent path as a source. (\$CFG_ROOT/ literal would be the
	# old source; \$CFG_ROOT/.codespace/ is the new one and is fine.)
	[[ "$log" != *"$CFG_ROOT/ "* ]]
	[[ "$log" != *"$CFG_ROOT/'"* ]]
}

@test "rsync_config_to_remote: no-op when \$CODESPACE_CONFIG_ROOT unset" {
	unset CODESPACE_CONFIG_ROOT
	: > "$SHIM_LOG"
	run cs_rsync_config_to_remote "user@host" "$REPO_ID"
	assert_success
	# stdout: remote relpath still printed (the caller may use it regardless)
	assert_output "codespace-config/$REPO_ID"
	# no rsync invoked
	[ ! -s "$SHIM_LOG" ] || ! grep -q '^rsync' "$SHIM_LOG"
}

@test "rsync_config_to_remote: no-op when src .codespace/ missing" {
	rm -rf "$CFG_ROOT/.codespace"
	: > "$SHIM_LOG"
	run cs_rsync_config_to_remote "user@host" "$REPO_ID"
	assert_success
	[ ! -s "$SHIM_LOG" ] || ! grep -q '^rsync' "$SHIM_LOG"
}

@test "rsync_config_to_remote: creates .codespace/ on remote before rsync" {
	export SHIM_LOG_STDIN=1
	cs_rsync_config_to_remote "user@host" "$REPO_ID" >/dev/null

	log="$(cat "$SHIM_LOG")"
	# heredoc body sent to ssh creates the .codespace/ subdir
	[[ "$log" == *"mkdir -p"*".codespace"* ]]
}
