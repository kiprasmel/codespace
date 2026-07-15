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

# ---- cs_stack_remote_setup_host: ships stack-post-create.sh ----
#
# stack-post-create.sh lives at $CODESPACE_CONFIG_ROOT/<rel_org>/stack-post-create.sh
# (next to stacks.json, NOT under .codespace/), so cs_rsync_config_to_remote
# (which only mirrors .codespace/) doesn't pick it up. Verify the stack-level
# host setup explicitly rsyncs it to the remote.

@test "stack_remote_setup_host: ships stack-post-create.sh to remote org config dir" {
	source_stack
	export SHIM_LOG_STDIN=1

	# layout: $HOME/projects/myorg/ holds the local repo; layer2 mirrors it.
	mkdir -p "$HOME/projects/myorg"
	export org_dir="$HOME/projects/myorg"
	mkdir -p "$CODESPACE_CONFIG_ROOT/projects/myorg"
	echo '#!/usr/bin/env bash' > "$CODESPACE_CONFIG_ROOT/projects/myorg/stack-post-create.sh"
	chmod +x "$CODESPACE_CONFIG_ROOT/projects/myorg/stack-post-create.sh"

	# minimal stacks.json so cs_stack_get_post_create_config returns the script
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/projects/myorg/stacks.json"
	export stacks_json="$CODESPACE_CONFIG_ROOT/projects/myorg/stacks.json"
	export stack_name="default"

	# stub out the layer-1 helpers (we only care about the rsync side-effects)
	cs_remote_self_install() { :; }
	cs_remote_probe() { :; }

	export remote_host="user@host"
	repo_names=(repo-a)

	run cs_stack_remote_setup_host
	assert_success

	log="$(cat "$SHIM_LOG")"
	# the parent dir on the remote is mkdir'd before the rsync of the script
	[[ "$log" == *"mkdir -p"*"codespace-config/projects/myorg"* ]]
	# rsync of the stack-post-create.sh source -> ~/codespace-config/<rel_org>/stack-post-create.sh
	[[ "$log" == *"rsync"*"$CODESPACE_CONFIG_ROOT/projects/myorg/stack-post-create.sh"* ]]
	[[ "$log" == *"user@host:codespace-config/projects/myorg/stack-post-create.sh"* ]]
}

@test "stack_remote_setup_host: skips ship when stack-post-create.sh missing locally" {
	source_stack
	export SHIM_LOG_STDIN=1

	mkdir -p "$HOME/projects/myorg"
	export org_dir="$HOME/projects/myorg"
	mkdir -p "$CODESPACE_CONFIG_ROOT/projects/myorg"
	# stacks.json present but no stack-post-create.sh next to it
	mk_stacks_json "$CODESPACE_CONFIG_ROOT/projects/myorg/stacks.json"
	export stacks_json="$CODESPACE_CONFIG_ROOT/projects/myorg/stacks.json"
	export stack_name="default"

	cs_remote_self_install() { :; }
	cs_remote_probe() { :; }

	export remote_host="user@host"
	repo_names=(repo-a)

	run cs_stack_remote_setup_host
	assert_success

	log="$(cat "$SHIM_LOG")"
	# nothing to ship -> no rsync of stack-post-create.sh
	[[ "$log" != *"stack-post-create.sh"* ]]
}

@test "stack_remote_setup_host: uses config_rel when org_dir differs from config path" {
	source_stack
	export SHIM_LOG_STDIN=1

	# org is ~/projects but user config lives under projects/layer2/projects
	mkdir -p "$HOME/projects"
	export org_dir="$HOME/projects"
	local cfg_root="$CODESPACE_CONFIG_ROOT/projects/layer2/projects"
	mkdir -p "$cfg_root"
	echo '#!/usr/bin/env bash' > "$cfg_root/stack-post-create.sh"
	chmod +x "$cfg_root/stack-post-create.sh"
	mk_stacks_json "$cfg_root/stacks.json"
	export stacks_json="$cfg_root/stacks.json"
	export stack_name="default"

	cs_remote_self_install() { :; }
	cs_remote_probe() { :; }

	export remote_host="user@host"
	repo_names=(repo-a)

	run cs_stack_remote_setup_host
	assert_success

	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"codespace-config/projects/layer2/projects/stack-post-create.sh"* ]]
	[[ "$log" != *"codespace-config/projects/stack-post-create.sh"* ]]
}
