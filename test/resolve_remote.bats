#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils

	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"
}

@test "resolve_remote: explicit flag value wins over everything" {
	export CS_DEFAULT_REMOTE="env-host"
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace"
	echo "repo-host" > "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace/remote"

	cd "$REPO"
	run cs_resolve_remote "explicit-host"
	assert_success
	assert_output "explicit-host"
}

@test "resolve_remote: sentinel falls through to env, then config" {
	export CS_DEFAULT_REMOTE="env-host"
	cd "$REPO"
	run cs_resolve_remote "$CS_REMOTE_USE_DEFAULT"
	assert_success
	assert_output "env-host"
}

@test "resolve_remote: per-repo .codespace/remote wins over per-org" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/.codespace"
	echo "repo-host" > "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace/remote"
	echo "org-host" > "$CODESPACE_CONFIG_ROOT/org/.codespace/remote"

	cd "$REPO"
	run cs_resolve_remote ""
	assert_success
	assert_output "repo-host"
}

@test "resolve_remote: falls back to per-org file when no repo file" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/.codespace"
	echo "  org-host  " > "$CODESPACE_CONFIG_ROOT/org/.codespace/remote"

	cd "$REPO"
	run cs_resolve_remote ""
	assert_success
	assert_output "org-host"
}

@test "resolve_remote: nothing configured -> non-zero, empty stdout" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	cd "$REPO"
	run cs_resolve_remote ""
	assert_failure
	assert_output ""
}
