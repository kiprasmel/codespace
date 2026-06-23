#!/usr/bin/env bats

# cs_resolve_hook is the generic hook resolver used by both `post-create`
# and `remote-bootstrap.sh`. It should behave identically for any hook name.

load helpers

setup() {
	common_setup
	source_utils

	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"
}

@test "resolve_hook: only repo-committed remote-bootstrap.sh -> uses repo path" {
	mkdir -p "$REPO/.codespace"
	echo '#!/bin/bash' > "$REPO/.codespace/remote-bootstrap.sh"
	chmod +x "$REPO/.codespace/remote-bootstrap.sh"

	run --separate-stderr cs_resolve_hook "$REPO" "remote-bootstrap.sh"
	assert_success
	assert_line --index 0 "$REPO/.codespace/remote-bootstrap.sh"
	assert_line --index 1 "$REPO/.codespace"
	[[ "$stderr" == *"using remote-bootstrap.sh from: $REPO/.codespace/remote-bootstrap.sh"* ]]
}

@test "resolve_hook: root-level repo hook is ignored (repo must use .codespace/)" {
	# a file named post-create at the repo root may be unrelated to codespace,
	# so it must NOT be picked up; only <repo>/.codespace/ counts for repos.
	echo '#!/bin/bash' > "$REPO/post-create"
	chmod +x "$REPO/post-create"

	run cs_resolve_hook "$REPO" "post-create"
	assert_failure
	assert_output ""
}

@test "resolve_hook: root-level config-dir hook (no .codespace/) resolves" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CFG="$CODESPACE_CONFIG_ROOT/org/myrepo"
	mkdir -p "$USER_CFG"
	touch "$USER_CFG/post-create"

	run --separate-stderr cs_resolve_hook "$REPO" "post-create"
	assert_success
	assert_line --index 0 "$USER_CFG/post-create"
	assert_line --index 1 "$USER_CFG"
	[[ "$stderr" == *"using post-create from: $USER_CFG/post-create"* ]]
}

@test "resolve_hook: config-dir .codespace/ hook wins over a root-level one" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CFG="$CODESPACE_CONFIG_ROOT/org/myrepo"
	mkdir -p "$USER_CFG/.codespace"
	touch "$USER_CFG/.codespace/post-create" "$USER_CFG/post-create"

	run --separate-stderr cs_resolve_hook "$REPO" "post-create"
	assert_success
	assert_line --index 0 "$USER_CFG/.codespace/post-create"
	assert_line --index 1 "$USER_CFG"
}

@test "resolve_hook: root-level config-dir remote-bootstrap.sh resolves too (generic)" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CFG="$CODESPACE_CONFIG_ROOT/org/myrepo"
	mkdir -p "$USER_CFG"
	echo '#!/bin/bash' > "$USER_CFG/remote-bootstrap.sh"
	chmod +x "$USER_CFG/remote-bootstrap.sh"

	run --separate-stderr cs_resolve_hook "$REPO" "remote-bootstrap.sh"
	assert_success
	assert_line --index 0 "$USER_CFG/remote-bootstrap.sh"
	assert_line --index 1 "$USER_CFG"
}

@test "resolve_hook: user-level wins, notes the ignored repo path" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CFG="$CODESPACE_CONFIG_ROOT/org/myrepo"
	mkdir -p "$USER_CFG/.codespace" "$REPO/.codespace"
	touch "$USER_CFG/.codespace/remote-bootstrap.sh" "$REPO/.codespace/remote-bootstrap.sh"

	run --separate-stderr cs_resolve_hook "$REPO" "remote-bootstrap.sh"
	assert_success
	assert_line --index 0 "$USER_CFG/.codespace/remote-bootstrap.sh"
	assert_line --index 1 "$USER_CFG"
	[[ "$stderr" == *"using remote-bootstrap.sh from: $USER_CFG/.codespace/remote-bootstrap.sh"* ]]
	[[ "$stderr" == *"ignoring repo-committed remote-bootstrap.sh at: $REPO/.codespace/remote-bootstrap.sh"* ]]
}

@test "resolve_hook: neither -> non-zero, empty stdout" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	run cs_resolve_hook "$REPO" "remote-bootstrap.sh"
	assert_failure
	assert_output ""
}

@test "resolve_hook: cs_resolve_post_create wrapper still works" {
	mkdir -p "$REPO/.codespace"
	echo '#!/bin/bash' > "$REPO/.codespace/post-create"
	chmod +x "$REPO/.codespace/post-create"

	# the existing wrapper API (used by cs_post_create + tests)
	run --separate-stderr cs_resolve_post_create "$REPO"
	assert_success
	assert_line --index 0 "$REPO/.codespace/post-create"
}

@test "resolve_hook: \$CS_POST_CREATE_CONFIG_DIR override wins (no \$CODESPACE_CONFIG_ROOT needed)" {
	# this is what the remote codespace flow does: pre-resolve the user config dir
	# locally and pass it to the remote via env, so the remote can find hooks
	# without having $CODESPACE_CONFIG_ROOT set itself.
	OVERRIDE="$SANDBOX/preresolved"
	mkdir -p "$OVERRIDE/.codespace" "$REPO/.codespace"
	touch "$OVERRIDE/.codespace/post-create" "$REPO/.codespace/post-create"

	unset CODESPACE_CONFIG_ROOT
	export CS_POST_CREATE_CONFIG_DIR="$OVERRIDE"

	run --separate-stderr cs_resolve_hook "$REPO" "post-create"
	assert_success
	assert_line --index 0 "$OVERRIDE/.codespace/post-create"
	assert_line --index 1 "$OVERRIDE"
	[[ "$stderr" == *"using post-create from: $OVERRIDE/.codespace/post-create"* ]]
	[[ "$stderr" == *"ignoring repo-committed post-create at: $REPO/.codespace/post-create"* ]]
}

@test "resolve_hook: \$CS_POST_CREATE_CONFIG_DIR set but missing -> falls back to repo" {
	mkdir -p "$REPO/.codespace"
	touch "$REPO/.codespace/post-create"

	export CS_POST_CREATE_CONFIG_DIR="$SANDBOX/does-not-exist"

	run --separate-stderr cs_resolve_hook "$REPO" "post-create"
	assert_success
	assert_line --index 0 "$REPO/.codespace/post-create"
	assert_line --index 1 "$REPO/.codespace"
}

@test "resolve_hook: \$CS_POST_CREATE_CONFIG_DIR override beats \$CODESPACE_CONFIG_ROOT" {
	# explicit override should take precedence over the env-derived user_base.
	OVERRIDE="$SANDBOX/preresolved"
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	USER_CFG="$CODESPACE_CONFIG_ROOT/org/myrepo"
	mkdir -p "$OVERRIDE/.codespace" "$USER_CFG/.codespace"
	echo "override" > "$OVERRIDE/.codespace/post-create"
	echo "via-config-root" > "$USER_CFG/.codespace/post-create"

	export CS_POST_CREATE_CONFIG_DIR="$OVERRIDE"

	run --separate-stderr cs_resolve_hook "$REPO" "post-create"
	assert_success
	assert_line --index 0 "$OVERRIDE/.codespace/post-create"
	assert_line --index 1 "$OVERRIDE"
}
