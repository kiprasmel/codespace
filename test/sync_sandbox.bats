#!/usr/bin/env bats

# Sync-side sandbox retargeting: the marker-driven decision in cs_sync_enter_sandbox
# (fresh -> new sandbox by default; opt-out -> host-FS; existing host-FS -> left
# alone; sandbox-backed -> re-ensured) plus the unified marker reader that lets
# either marker (.codespace/sync or .codespace-remote) drive sandbox detection.
# The real DinD orchestrator is mocked via the ssh shim's canned `sandbox ensure`
# reply (same pattern as sandbox_retarget.bats).

load helpers

setup() {
	common_setup
	source_utils   # codespace-remote + the cloud sandbox glue (cs_sandbox_*)
	source_sync    # cs_sync_enter_sandbox / cs_sync_marker_*
	mkdir -p "$HOME/.ssh"
	printf 'ssh-ed25519 AAAAPUB me@mac\n' > "$HOME/.ssh/id_ed25519.pub"
}

# canned host-orchestrator `sandbox ensure` reply for the ssh shim
ensure_reply() {
	printf 'alias=%s\ncontainer=%s\nhostname=127.0.0.1\nport=%s\n' \
		"cs-sandbox-feature_foo" "cs-sandbox-feature_foo" "49177"
}

# --- unified marker reader ----------------------------------------------------

@test "cs_any_marker_get: .codespace/sync wins per-key, falls back to the stub" {
	d="$BATS_TEST_TMPDIR/cs"; mkdir -p "$d"
	cs_remote_marker_write "$d" "host=white-monster" "branch=feat" "sandbox_host=white-monster"
	# only the stub is present -> reads it
	assert_equal "$(cs_any_marker_get "$d" host)" "white-monster"
	assert_equal "$(cs_any_marker_get "$d" sandbox_host)" "white-monster"
	# a live sync marker wins per-key...
	cs_sync_marker_write "$d" "host=cs-sandbox-feature_foo" "branch=feat"
	assert_equal "$(cs_any_marker_get "$d" host)" "cs-sandbox-feature_foo"
	# ...but a key only in the stub still resolves
	assert_equal "$(cs_any_marker_get "$d" sandbox_host)" "white-monster"
}

@test "cs_remote_marker_is_sandbox: true from a .codespace/sync marker too" {
	d="$BATS_TEST_TMPDIR/sbx"; mkdir -p "$d"
	cs_sync_marker_write "$d" "host=cs-sandbox-feature_foo" "sandbox_host=white-monster"
	run cs_remote_marker_is_sandbox "$d"
	assert_success

	d2="$BATS_TEST_TMPDIR/hostfs"; mkdir -p "$d2"
	cs_sync_marker_write "$d2" "host=white-monster"   # host-FS: no sandbox fields
	run cs_remote_marker_is_sandbox "$d2"
	assert_failure
}

# --- cs_sync_enter_sandbox: the four quadrants --------------------------------

@test "cs_sync_enter_sandbox: fresh + CS_SANDBOX=0 is a no-op (host-FS escape hatch)" {
	install_ssh_shims
	export CS_SANDBOX=0
	d="$BATS_TEST_TMPDIR/fresh"; mkdir -p "$d"
	CS_SANDBOX_ALIAS="sentinel"
	cs_sync_enter_sandbox "$d" "white-monster" "feat"
	[ -z "$CS_SANDBOX_ALIAS" ]                 # reset, no retarget
	run cat "$SHIM_LOG"
	refute_output --partial "sandbox ensure"   # never drove the orchestrator
}

@test "cs_sync_enter_sandbox: fresh + sandbox active retargets to the alias + exports base" {
	install_ssh_shims
	export SHIM_LOG_STDIN=1
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT
	export CS_SANDBOX=1
	d="$BATS_TEST_TMPDIR/fresh"; mkdir -p "$d"
	cs_sync_enter_sandbox "$d" "white-monster" "feature/foo"
	[ "$CS_SANDBOX_ALIAS" = "cs-sandbox-feature_foo" ]
	[ "$CS_WORKTREE_BASE" = "/codespaces/feature_foo" ]
	run cat "$SHIM_LOG"
	assert_output --partial "sandbox ensure"
}

@test "cs_sync_enter_sandbox: an existing host-FS codespace is left as-is (not migrated)" {
	install_ssh_shims
	export CS_SANDBOX=1                        # even with the sandbox default on
	d="$BATS_TEST_TMPDIR/hostfs"; mkdir -p "$d"
	cs_sync_marker_write "$d" "host=white-monster" "branch=feat"   # no sandbox fields
	CS_SANDBOX_ALIAS="sentinel"
	cs_sync_enter_sandbox "$d" "white-monster" "feat"
	[ -z "$CS_SANDBOX_ALIAS" ]                 # honored the existing layout
	run cat "$SHIM_LOG"
	refute_output --partial "sandbox ensure"
}

@test "cs_sync_enter_sandbox: a sandbox-backed codespace is re-ensured (same slug)" {
	install_ssh_shims
	export SHIM_LOG_STDIN=1
	SSH_NEXT_STDOUT="$(ensure_reply)" export SSH_NEXT_STDOUT
	unset CS_SANDBOX                           # auto: an existing sandbox marker still re-ensures
	d="$BATS_TEST_TMPDIR/sbx"; mkdir -p "$d"
	cs_sync_marker_write "$d" \
		"host=cs-sandbox-feature_foo" "branch=feature/foo" \
		"sandbox_host=white-monster" "worktree_base=/codespaces/feature_foo"
	cs_sync_enter_sandbox "$d" "white-monster" "feature/foo"
	[ "$CS_SANDBOX_ALIAS" = "cs-sandbox-feature_foo" ]
	[ "$CS_WORKTREE_BASE" = "/codespaces/feature_foo" ]
	run cat "$SHIM_LOG"
	assert_output --partial "sandbox ensure"
}
