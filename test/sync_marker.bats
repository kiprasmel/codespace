#!/usr/bin/env bats

# .codespace/sync marker: write / get / git-exclude.

load helpers

setup() {
	common_setup
	source_sync
}

@test "marker: write then get round-trips values" {
	mkrepo "$SANDBOX/r"
	cs_sync_marker_write "$SANDBOX/r" \
		"host=user@host" "relpath=codespace/org/repo_feat" "branch=feat" \
		"synced_commit=abc123"

	run cs_sync_marker_get "$SANDBOX/r" host
	assert_output "user@host"
	run cs_sync_marker_get "$SANDBOX/r" branch
	assert_output "feat"
	run cs_sync_marker_get "$SANDBOX/r" synced_commit
	assert_output "abc123"
}

@test "marker: missing key / missing file -> empty" {
	mkrepo "$SANDBOX/r"
	run cs_sync_marker_get "$SANDBOX/r" nope
	assert_output ""
	run cs_sync_marker_get "$SANDBOX/empty" host
	assert_output ""
}

@test "marker: git-excludes .codespace/sync in a work tree" {
	mkrepo "$SANDBOX/r"
	cs_sync_marker_write "$SANDBOX/r" "host=h"
	run grep -qxF ".codespace/sync" "$SANDBOX/r/.git/info/exclude"
	assert_success
}
