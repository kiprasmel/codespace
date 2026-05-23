#!/usr/bin/env bats

# cs_ship_files_to_remote — given a manifest of `repo:<f>` / `config:<f>`
# lines, rsyncs each file from its local source to the remote worktree.

load helpers

setup() {
	common_setup
	source_utils
	install_ssh_shims

	# local base repo at the user's "current" location
	REPO="$SANDBOX/myorg/myrepo"
	mkrepo "$REPO"
	echo "secret" > "$REPO/.env"
	mkdir -p "$REPO/etc"
	echo "agents" > "$REPO/etc/agents.md"

	# layer2 config dir
	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	REPO_ID="myorg/myrepo"
	mkdir -p "$CODESPACE_CONFIG_ROOT/$REPO_ID"
	echo "shared" > "$CODESPACE_CONFIG_ROOT/$REPO_ID/AGENTS.md"

	cd "$REPO"
	DST_REL="codespace/$REPO_ID/myrepo_feat"

	MANIFEST="$BATS_TEST_TMPDIR/manifest"
}

@test "ship: empty manifest -> noop, no rsync" {
	: > "$MANIFEST"
	run cs_ship_files_to_remote "user@host" "$DST_REL" "$MANIFEST" "$REPO_ID"
	assert_success
	! grep -q '^rsync' "$SHIM_LOG"
}

@test "ship: repo:<f> rsyncs from base repo to dst_rel/<f>" {
	cat > "$MANIFEST" <<EOF
repo:.env
EOF

	run cs_ship_files_to_remote "user@host" "$DST_REL" "$MANIFEST" "$REPO_ID"
	assert_success

	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"rsync"*"$REPO/.env"* ]]
	[[ "$log" == *"user@host:$DST_REL/.env"* ]]
}

@test "ship: config:<f> rsyncs from CODESPACE_CONFIG_ROOT/repo_id to dst_rel/<f>" {
	cat > "$MANIFEST" <<EOF
config:AGENTS.md
EOF

	run cs_ship_files_to_remote "user@host" "$DST_REL" "$MANIFEST" "$REPO_ID"
	assert_success

	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"rsync"*"$CODESPACE_CONFIG_ROOT/$REPO_ID/AGENTS.md"* ]]
	[[ "$log" == *"user@host:$DST_REL/AGENTS.md"* ]]
}

@test "ship: pre-creates parent dirs on remote in one ssh call" {
	cat > "$MANIFEST" <<EOF
repo:etc/agents.md
EOF

	export SHIM_LOG_STDIN=1
	run cs_ship_files_to_remote "user@host" "$DST_REL" "$MANIFEST" "$REPO_ID"
	assert_success

	log="$(cat "$SHIM_LOG")"
	# the parent-dir bash script (sent via stdin) contains mkdir -p for etc/
	[[ "$log" == *"mkdir -p"* ]]
	[[ "$log" == *"etc/"* ]]
}

@test "ship: missing local source -> warn + skip (no rsync), other entries proceed" {
	cat > "$MANIFEST" <<EOF
repo:does-not-exist
repo:.env
EOF

	run cs_ship_files_to_remote "user@host" "$DST_REL" "$MANIFEST" "$REPO_ID"
	assert_success
	[[ "$output" == *"declared file not found locally"* ]]
	[[ "$output" == *"does-not-exist"* ]]

	log="$(cat "$SHIM_LOG")"
	# .env IS rsynced
	[[ "$log" == *"$REPO/.env"* ]]
	# the missing one is NOT
	[[ "$log" != *"does-not-exist"* ]]
}

@test "ship: config:<f> with \$CODESPACE_CONFIG_ROOT unset -> warn + skip" {
	cat > "$MANIFEST" <<EOF
config:AGENTS.md
EOF

	unset CODESPACE_CONFIG_ROOT
	run cs_ship_files_to_remote "user@host" "$DST_REL" "$MANIFEST" "$REPO_ID"
	assert_success
	[[ "$output" == *"CODESPACE_CONFIG_ROOT unset"* ]]
	! grep -q "AGENTS.md" "$SHIM_LOG" || ! grep -q '^rsync' "$SHIM_LOG"
}

@test "ship: unknown manifest kind -> warn + skip" {
	cat > "$MANIFEST" <<EOF
weird:foo
repo:.env
EOF

	run cs_ship_files_to_remote "user@host" "$DST_REL" "$MANIFEST" "$REPO_ID"
	assert_success
	[[ "$output" == *"unknown manifest kind 'weird'"* ]]
	# .env still ships
	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"$REPO/.env"* ]]
}
