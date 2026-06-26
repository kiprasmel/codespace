#!/usr/bin/env bats

# The per-codespace sync lock keys on a *canonical* path, so any spelling of the
# same codespace (symlink, trailing slash, /var vs /private/var) serializes
# against one lock -- otherwise a hook-triggered background sync races a manual.

load helpers

setup() {
	common_setup
	source_sync
}

@test "lock: symlinked + trailing-slash spellings of one codespace share a lock" {
	mkdir -p "$BATS_TEST_TMPDIR/cs"
	ln -s "$BATS_TEST_TMPDIR/cs" "$BATS_TEST_TMPDIR/link"

	local l1 l2
	l1="$(cs_sync_lock_acquire "$BATS_TEST_TMPDIR/cs")"
	rm -rf "$l1"
	l2="$(cs_sync_lock_acquire "$BATS_TEST_TMPDIR/link/")"
	rm -rf "$l2"

	[ -n "$l1" ]
	[ "$l1" = "$l2" ]
}

@test "lock: distinct codespaces get distinct locks" {
	mkdir -p "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"

	local la lb
	la="$(cs_sync_lock_acquire "$BATS_TEST_TMPDIR/a")"
	rm -rf "$la"
	lb="$(cs_sync_lock_acquire "$BATS_TEST_TMPDIR/b")"
	rm -rf "$lb"

	[ "$la" != "$lb" ]
}

@test "lock: an unresolvable path still locks (falls back to the raw spelling)" {
	local l
	l="$(cs_sync_lock_acquire "$BATS_TEST_TMPDIR/does-not-exist")"
	[ -n "$l" ]
	[ -d "$l" ]
	rm -rf "$l"
}
