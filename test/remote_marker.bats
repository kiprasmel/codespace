#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils

	STUB="$SANDBOX/stub"
	mkdir -p "$STUB"
}

@test "remote_marker: write + read round-trip" {
	cs_remote_marker_write "$STUB" \
		"host=user@example.com" \
		"relpath=codespace/org/repo_feat" \
		"kind=worktree" \
		"repo_id=org/repo" \
		"branch=feat"

	[ -f "$STUB/.codespace-remote" ]

	run cs_remote_marker_get "$STUB" host
	assert_output "user@example.com"

	run cs_remote_marker_get "$STUB" relpath
	assert_output "codespace/org/repo_feat"

	run cs_remote_marker_get "$STUB" kind
	assert_output "worktree"

	run cs_remote_marker_get "$STUB" branch
	assert_output "feat"
}

@test "remote_marker: cs_remote_marker presence check" {
	run cs_remote_marker "$STUB"
	assert_failure

	cs_remote_marker_write "$STUB" "host=h"
	run cs_remote_marker "$STUB"
	assert_success
}

@test "remote_marker: missing key returns empty" {
	cs_remote_marker_write "$STUB" "host=h"
	run cs_remote_marker_get "$STUB" nope
	assert_success
	assert_output ""
}

@test "remote_marker: value containing '=' is preserved" {
	cs_remote_marker_write "$STUB" "url=https://x?a=1&b=2"
	run cs_remote_marker_get "$STUB" url
	assert_output "https://x?a=1&b=2"
}
