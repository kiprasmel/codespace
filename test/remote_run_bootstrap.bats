#!/usr/bin/env bats

# Verify cs_remote_run_bootstrap:
# - ALWAYS invokes the script (no "presence marker" check)
# - passes the documented env block (CS_HOST, CS_REPO_ID, CS_BRANCH, ...)
# - propagates non-zero exit codes

load helpers

setup() {
	common_setup
	source_utils
	install_ssh_shims
	# this test asserts on the stdin script body; tell the ssh shim to log it.
	export SHIM_LOG_STDIN=1
}

@test "remote_run_bootstrap: invokes ssh exactly once with the script body on stdin" {
	run cs_remote_run_bootstrap "user@host" "myorg/myrepo" \
		"codespace/myorg/myrepo_feat" "codespace/myorg/myrepo" "feat"
	assert_success

	# only one ssh call expected (no probe / pre-check)
	run grep -c '^ssh ' "$SHIM_LOG"
	assert_output "1"
}

@test "remote_run_bootstrap: passes positional args matching the env block" {
	run cs_remote_run_bootstrap "user@host" "myorg/myrepo" \
		"codespace/myorg/myrepo_feat" "codespace/myorg/myrepo" "feat" "codespace-config/myorg/myrepo"
	assert_success

	# Log uses %q quoting (escapes spaces). Look for distinctive substrings.
	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"bash"*"-s"* ]] \
		|| { echo "log: $log"; false; }
	[[ "$log" == *"user@host"* ]]
	[[ "$log" == *"myorg/myrepo"* ]]
	[[ "$log" == *"feat"* ]]
	[[ "$log" == *"codespace/myorg/myrepo_feat"* ]]
	[[ "$log" == *"codespace-config/myorg/myrepo"* ]]

	# Stdin (the bash script body) carries the documented env block.
	[[ "$log" == *"export CS_HOST="* ]]
	[[ "$log" == *"export CS_REPO_ID="* ]]
	[[ "$log" == *"export CS_BRANCH="* ]]
	[[ "$log" == *"export CS_REMOTE_PATH="* ]]
	[[ "$log" == *"export CS_REMOTE_BASE_REPO="* ]]
	[[ "$log" == *"export CS_POST_CREATE_CONFIG_DIR="* ]]
}

@test "remote_run_bootstrap: regression — no marker file created or checked locally" {
	# Bootstrap is "always run; idempotency is the script's job" — so the local
	# state must not gain any presence-marker files.
	cs_remote_run_bootstrap "user@host" "org/repo" "codespace/org/repo_feat" "codespace/org/repo" "feat" >/dev/null

	# nothing under ~/.cache/codespace/* or similar should appear
	[ ! -d "$HOME/.cache/codespace" ] || {
		run find "$HOME/.cache/codespace" -type f
		[ -z "$output" ] || { echo "unexpected files: $output"; false; }
	}
}

@test "remote_run_bootstrap: failure exit propagates" {
	export SSH_NEXT_RC=42
	run cs_remote_run_bootstrap "user@host" "org/repo" "codespace/org/repo_feat" "codespace/org/repo" "feat"
	assert_failure
	[ "$status" -eq 42 ]
}
