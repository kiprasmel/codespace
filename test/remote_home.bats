#!/usr/bin/env bats

# cs_remote_home — resolves remote $HOME via one ssh round-trip, memoized.

load helpers

setup() {
	common_setup
	source_utils
	install_ssh_shims
}

@test "remote_home: returns the remote \$HOME from ssh stdout" {
	SSH_NEXT_STDOUT="/home/ubuntu" run cs_remote_home "user@host"
	assert_success
	assert_output "/home/ubuntu"
}

@test "remote_home: memoized — second call reuses cached value, no extra ssh" {
	# 1st call (uncached) hits ssh, 2nd should not.
	SSH_NEXT_STDOUT="/home/alice" cs_remote_home "alice@h" >/dev/null

	calls_before="$(wc -l < "$SHIM_LOG")"
	# Without the override set, if a 2nd ssh call happened, the shim would
	# return empty stdout and the cs_remote_home function would think the
	# value wasn't memoized. Memoization avoids the call entirely.
	run cs_remote_home "alice@h"
	assert_success
	assert_output "/home/alice"

	calls_after="$(wc -l < "$SHIM_LOG")"
	[ "$calls_before" = "$calls_after" ]
}

@test "remote_home: distinct hosts cache independently" {
	SSH_NEXT_STDOUT="/home/a" cs_remote_home "a@h1" >/dev/null
	SSH_NEXT_STDOUT="/home/b" cs_remote_home "b@h2" >/dev/null

	run cs_remote_home "a@h1"
	assert_output "/home/a"
	run cs_remote_home "b@h2"
	assert_output "/home/b"
}

@test "remote_home: ssh failure returns non-zero" {
	SSH_NEXT_RC=1 run cs_remote_home "user@bad"
	assert_failure
}

@test "remote_home: empty ssh stdout returns non-zero" {
	# default shim (no override) prints nothing -> should fail
	run cs_remote_home "user@empty"
	assert_failure
}
