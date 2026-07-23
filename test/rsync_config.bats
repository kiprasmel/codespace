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

# ---- cs_stack_remote_setup_host: mirrors org-config-root top-level files ----
#
# stack-post-create.sh AND the siblings it may ln/cp (AGENTS.md, TODO.md, ...)
# live at $CODESPACE_CONFIG_ROOT/<rel_org>/ (next to stacks.json, NOT under
# .codespace/), so cs_rsync_config_to_remote (which only mirrors .codespace/)
# doesn't pick them up. The stack-level host setup mirrors the org-config root's
# TOP-LEVEL FILES to the remote so STACK_CONFIG_ROOT is complete and
# stack-post-create.sh's ln/cp of siblings resolve; per-repo subdirs + the
# .codespace/ dir are excluded here (shipped separately).

# (functional real-rsync coverage — that AGENTS.md/TODO.md actually land and
# subdirs don't — lives in stack_config_shipping.bats, which uses the
# local-remote harness with a genuine rsync. Here we only assert the invocation
# form, since this file's setup() installs logging shims.)

@test "stack_remote_setup_host: mirror source/dest use config_rel, not the shorter org path" {
	source_stack
	export SHIM_LOG_STDIN=1
	install_ssh_shims

	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	# org is ~/projects but user config lives under projects/layer2/projects
	mkdir -p "$HOME/projects"; export org_dir="$HOME/projects"
	local cfg="$CODESPACE_CONFIG_ROOT/projects/layer2/projects"
	mkdir -p "$cfg"
	echo '#!/usr/bin/env bash' > "$cfg/stack-post-create.sh"; chmod +x "$cfg/stack-post-create.sh"
	echo agents > "$cfg/AGENTS.md"
	mk_stacks_json "$cfg/stacks.json"
	export stacks_json="$cfg/stacks.json"
	export stack_name="default"

	cs_remote_self_install() { :; }
	cs_remote_probe() { :; }
	export remote_host="user@host"
	repo_names=()

	run cs_stack_remote_setup_host
	assert_success

	log="$(cat "$SHIM_LOG")"
	# the parent dir on the remote is mkdir'd before the mirror rsync
	[[ "$log" == *"mkdir -p"*"codespace-config/projects/layer2/projects"* ]]
	# mirror rsync: top-level-files filter, source = org-config-root dir,
	# dest = remote config dir keyed by config_rel (not the shorter org path)
	[[ "$log" == *"--filter="* ]]
	[[ "$log" == *"$cfg/"* ]]
	[[ "$log" == *"user@host:codespace-config/projects/layer2/projects/"* ]]
	[[ "$log" != *"codespace-config/projects/stack-post-create.sh"* ]]
}
