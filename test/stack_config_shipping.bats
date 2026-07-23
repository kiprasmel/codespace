#!/usr/bin/env bats

# Functional coverage for cs_stack_remote_setup_host's org-config-root shipping.
#
# stack-post-create.sh AND the siblings it may ln/cp (AGENTS.md, TODO.md, ...)
# live at the org-config root (next to stacks.json), NOT under .codespace/, so
# cs_rsync_config_to_remote (which mirrors only .codespace/) never ships them.
# The stack-level host setup mirrors the root's TOP-LEVEL FILES so
# STACK_CONFIG_ROOT is complete on the remote and the ln/cp resolve; per-repo
# subdirs are excluded (shipped separately).
#
# Uses the local-remote harness so rsync ACTUALLY transfers. This file's setup()
# deliberately does NOT install the logging ssh/rsync shims: setup_local_remote
# captures the real rsync at call time, and a logging shim on PATH would be
# captured as "real" and silently copy nothing.

load helpers

setup() {
	common_setup
	source_utils
	source_stack
	setup_local_remote      # real rsync (rewrites host:path) + local-exec ssh
}

@test "stack_remote_setup_host: mirrors org-config-root top-level files (post-create + AGENTS.md/TODO.md), excludes subdirs" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	local cfg="$CODESPACE_CONFIG_ROOT/projects/myorg"
	mkdir -p "$cfg/.codespace" "$cfg/repo-a"
	echo '#!/usr/bin/env bash' > "$cfg/stack-post-create.sh"; chmod +x "$cfg/stack-post-create.sh"
	echo agents > "$cfg/AGENTS.md"
	echo todo   > "$cfg/TODO.md"
	echo hook   > "$cfg/.codespace/post-create"
	echo readme > "$cfg/repo-a/README.md"
	mk_stacks_json "$cfg/stacks.json"
	export stacks_json="$cfg/stacks.json"
	export stack_name="default"
	mkdir -p "$HOME/projects/myorg"; export org_dir="$HOME/projects/myorg"

	cs_remote_self_install() { :; }
	cs_remote_probe() { :; }
	export remote_host="user@host"
	repo_names=()

	run cs_stack_remote_setup_host
	assert_success

	local rcfg="$REMOTE_HOME/codespace-config/projects/myorg"
	# top-level files (stack-post-create.sh + the siblings it links) landed remote
	[ -f "$rcfg/stack-post-create.sh" ]
	[ -f "$rcfg/AGENTS.md" ]
	[ -f "$rcfg/TODO.md" ]
	[ -f "$rcfg/stacks.json" ]
	# .codespace/ still ships (via cs_rsync_config_to_remote), separately
	[ -f "$rcfg/.codespace/post-create" ]
	# the "- /*/" filter excluded top-level subdirs; repo_names=() so repo-a is
	# not shipped separately either -> it must not appear under the mirror dest.
	[ ! -e "$rcfg/repo-a" ]
}
