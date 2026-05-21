#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils
	install_ssh_shims
}

@test "remote_self_install: rsyncs codespace scripts and chmods them" {
	run cs_remote_self_install "user@host"
	assert_success

	# log uses %q quoting (spaces -> backslash-space). Use substring checks.
	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"user@host"* ]]
	[[ "$log" == *"mkdir"*".local/bin"* ]]
	[[ "$log" == *"rsync"* ]]
	for f in codespace codespace-utils codespace-worktree codespace-stack codespace-stack-ls codespace-find; do
		[[ "$log" == *"$f"* ]] || { echo "missing in rsync log: $f"; false; }
	done
	[[ "$log" == *"user@host:.local/bin/"* ]]
	[[ "$log" == *"chmod"*".local/bin/codespace"* ]]
}

@test "remote_self_install: fails non-zero if final exec test fails" {
	# 1st (mkdir): ok, 2nd (chmod): ok, 3rd (test -x): fail.
	# But the SSH_NEXT_RC override only applies once and is consumed; we need a counter.
	# Simulate by writing a counter shim that fails on the 3rd call.
	cat > "$SHIM_BIN/ssh" <<'SSH'
#!/usr/bin/env bash
N_FILE="$BATS_TEST_TMPDIR/ssh.n"
n="$(cat "$N_FILE" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" > "$N_FILE"
{ printf 'ssh#%d' "$n"; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'; } >> "$SHIM_LOG"
[ "$n" -ge 3 ] && exit 1 || exit 0
SSH
	chmod +x "$SHIM_BIN/ssh"

	run cs_remote_self_install "user@host"
	assert_failure
	[[ "$output" == *"err: [user@host] codespace not runnable"* ]]
}
