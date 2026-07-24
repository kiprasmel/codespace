#!/usr/bin/env bats

# `codespace dev` USER SURFACE:
#   - cs_dev_read_markers: line-based (host/branch/kind/repo_id/relpath) read of
#     whichever marker exists (.codespace-remote stub wins per-key).
#   - `codespace dev status [path]` / `codespace dev stop [path]`: the friendly
#     verbs that infer the slug from the cwd/path and operate on the LOCAL session
#     for a plain local codespace (no remote marker), read-only for status.

load helpers

setup() {
	common_setup
	export CODESPACE_CONFIG_ROOT="$BATS_TEST_TMPDIR/cfg"
	mkdir -p "$CODESPACE_CONFIG_ROOT"
	source_dev
}

# --- cs_dev_read_markers ----------------------------------------------------

@test "read_markers: bare dir (no marker) yields all-empty fields" {
	mkdir -p "$BATS_TEST_TMPDIR/plain"
	run cs_dev_read_markers "$BATS_TEST_TMPDIR/plain"
	assert_success
	# five empty fields; bats strips trailing newlines -> empty $output
	assert_output ""
}

@test "read_markers: reads host/branch/kind/repo_id/relpath from a .codespace-remote stub" {
	d="$BATS_TEST_TMPDIR/cs"
	cs_remote_marker_write "$d" \
		"host=white-monster" "branch=feature/foo" "kind=stack" \
		"repo_id=/sintra/core" "relpath=codespace/sintra/stack_feature_foo"
	meta="$(cs_dev_read_markers "$d")"
	assert_equal "$(sed -n '1p' <<<"$meta")" "white-monster"
	assert_equal "$(sed -n '2p' <<<"$meta")" "feature/foo"
	assert_equal "$(sed -n '3p' <<<"$meta")" "stack"
	assert_equal "$(sed -n '4p' <<<"$meta")" "/sintra/core"
	assert_equal "$(sed -n '5p' <<<"$meta")" "codespace/sintra/stack_feature_foo"
}

# --- dev status / dev stop (plain local codespace) --------------------------

@test "dispatch: 'codespace dev status <dir>' reports LOCAL, read-only, exits 0" {
	mkdir -p "$BATS_TEST_TMPDIR/wt-alpha"
	run "$REPO_ROOT/codespace" dev status "$BATS_TEST_TMPDIR/wt-alpha"
	assert_success
	assert_output --partial "— local:"
	assert_output --partial "no forwarded session"
}

@test "dispatch: 'codespace dev stop <dir>' tears the local session down, exits 0" {
	mkdir -p "$BATS_TEST_TMPDIR/wt-beta"
	run "$REPO_ROOT/codespace" dev stop "$BATS_TEST_TMPDIR/wt-beta"
	assert_success
	assert_output --partial "dev stopped for 'wt-beta'"
}

@test "dispatch: 'codespace dev status' with a forwarded session lists the service urls" {
	# pre-seed a session file for slug 'wt-gamma' (host_key 'local' in local mode)
	mkdir -p "$BATS_TEST_TMPDIR/wt-gamma"
	plan="$(printf 'web\t3000\thttps\n' | cs_dev_build_port_plan "wt-gamma" "" 1)"
	sf="$(cs_dev_session_file "local" "wt-gamma")"
	cs_dev_session_write "$sf" "" "" "" "wt-gamma" "wt-gamma" "0" "1" "$plan"
	run "$REPO_ROOT/codespace" dev status "$BATS_TEST_TMPDIR/wt-gamma"
	assert_success
	assert_output --partial "services:"
	assert_output --partial "https://wt-gamma.localhost"
}
