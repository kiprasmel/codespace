#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils

	# create a real git repo at $HOME/org/myrepo so cs_config_path / cs_repo_id work
	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"
}

@test "resolve_post_create: only repo-committed -> uses repo, notes 'using'" {
	mkdir -p "$REPO/.codespace"
	cat > "$REPO/.codespace/post-create" <<'EOF'
#!/usr/bin/env bash
:
EOF
	chmod +x "$REPO/.codespace/post-create"

	run --separate-stderr cs_resolve_post_create "$REPO"
	assert_success
	assert_line --index 0 "$REPO/.codespace/post-create"
	assert_line --index 1 "$REPO/.codespace"
	[[ "$stderr" == *"note: using post-create from: $REPO/.codespace/post-create"* ]]
	refute [ "${stderr:-}" = "*ignoring*" ]
}

@test "resolve_post_create: only user-level -> config base is config root, not .codespace/" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CONFIG_ROOT="$CODESPACE_CONFIG_ROOT/org/myrepo"
	USER_CS_DIR="$USER_CONFIG_ROOT/.codespace"
	mkdir -p "$USER_CS_DIR"
	cat > "$USER_CS_DIR/post-create" <<'EOF'
#!/usr/bin/env bash
:
EOF
	chmod +x "$USER_CS_DIR/post-create"

	run --separate-stderr cs_resolve_post_create "$REPO"
	assert_success
	assert_line --index 0 "$USER_CS_DIR/post-create"
	# active base = config root (parent of .codespace/), so link-files-from-config
	# resolves files sitting alongside .codespace/, matching the existing convention.
	assert_line --index 1 "$USER_CONFIG_ROOT"
	[[ "$stderr" == *"note: using post-create from: $USER_CS_DIR/post-create"* ]]
	[[ "$stderr" != *"ignoring"* ]]
}

@test "resolve_post_create: both -> user wins, notes ignored repo path" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CONFIG_ROOT="$CODESPACE_CONFIG_ROOT/org/myrepo"
	USER_CS_DIR="$USER_CONFIG_ROOT/.codespace"
	mkdir -p "$USER_CS_DIR" "$REPO/.codespace"
	touch "$USER_CS_DIR/post-create" "$REPO/.codespace/post-create"
	chmod +x "$USER_CS_DIR/post-create" "$REPO/.codespace/post-create"

	run --separate-stderr cs_resolve_post_create "$REPO"
	assert_success
	assert_line --index 0 "$USER_CS_DIR/post-create"
	assert_line --index 1 "$USER_CONFIG_ROOT"
	[[ "$stderr" == *"note: using post-create from: $USER_CS_DIR/post-create"* ]]
	[[ "$stderr" == *"note: ignoring repo-committed post-create at: $REPO/.codespace/post-create"* ]]
}

@test "resolve_post_create: neither -> non-zero, empty stdout" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"

	run --separate-stderr cs_resolve_post_create "$REPO"
	assert_failure
	assert_output ""
}

@test "resolve_post_create: no CODESPACE_CONFIG_ROOT + repo-committed works" {
	unset CODESPACE_CONFIG_ROOT
	mkdir -p "$REPO/.codespace"
	touch "$REPO/.codespace/post-create"
	chmod +x "$REPO/.codespace/post-create"

	run --separate-stderr cs_resolve_post_create "$REPO"
	assert_success
	assert_line --index 0 "$REPO/.codespace/post-create"
	assert_line --index 1 "$REPO/.codespace"
}
