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
