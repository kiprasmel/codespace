#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils
	install_ssh_shims
}

@test "remote_probe: all tools present -> zero" {
	# 1st ssh call returns empty -> "no missing"
	export SSH_NEXT_STDOUT=""
	run --separate-stderr cs_remote_probe "user@host"
	assert_success
}

@test "remote_probe: missing tools -> non-zero with apt suggestion on debian" {
	# Use a counter shim: 1st call returns "jq rsync", 2nd returns "ubuntu".
	cat > "$SHIM_BIN/ssh" <<'SSH'
#!/usr/bin/env bash
N_FILE="$BATS_TEST_TMPDIR/ssh.n"
n="$(cat "$N_FILE" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" > "$N_FILE"
case "$n" in
	1) echo "jq rsync" ;;
	2) echo "ubuntu" ;;
esac
exit 0
SSH
	chmod +x "$SHIM_BIN/ssh"

	run --separate-stderr cs_remote_probe "user@host"
	assert_failure
	[[ "$stderr" == *"missing required tools: jq rsync"* ]]
	[[ "$stderr" == *"sudo apt-get install -y jq rsync"* ]]
}

@test "remote_probe: missing tools on darwin -> brew suggestion" {
	cat > "$SHIM_BIN/ssh" <<'SSH'
#!/usr/bin/env bash
N_FILE="$BATS_TEST_TMPDIR/ssh.n"
n="$(cat "$N_FILE" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" > "$N_FILE"
case "$n" in
	1) echo "git" ;;
	2) echo "Darwin" ;;
esac
exit 0
SSH
	chmod +x "$SHIM_BIN/ssh"

	run --separate-stderr cs_remote_probe "user@host"
	assert_failure
	[[ "$stderr" == *"missing required tools: git"* ]]
	[[ "$stderr" == *"brew install git"* ]]
}
