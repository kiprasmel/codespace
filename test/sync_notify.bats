#!/usr/bin/env bats

# Pure test for the debounced notification reader: it turns a stream of
# `name<TAB>status<TAB>cycles` lines (as emitted by mutagen's monitor template)
# into clean "syncing / synced" notices. CS_NOTIFY_DEBOUNCE=0 + EOF make the
# flush deterministic.

load helpers

setup() {
	common_setup
	source_sync
	export CS_NOTIFY_DEBOUNCE=0
	IN="$BATS_TEST_TMPDIR/notify.in"
}

@test "notify: a Watching->working->Watching cycle prints syncing then synced" {
	printf 's1\tWatching\t5\ns1\tStaging Beta\t5\ns1\tWatching\t6\n' > "$IN"
	run cs_sync_notify_reader "s1=feat" < "$IN"
	assert_success
	assert_output --partial "syncing feat"
	assert_output --partial "synced feat"
	# ordering: the syncing notice precedes the synced notice.
	[[ "$output" == *"syncing feat"*"synced feat"* ]]
}

@test "notify: a completed cycle alone (no caught activity) prints only synced" {
	printf 's1\tWatching\t5\ns1\tWatching\t8\n' > "$IN"
	run cs_sync_notify_reader "s1=feat" < "$IN"
	assert_success
	assert_output --partial "synced feat"
	refute_output --partial "syncing feat"
}

@test "notify: the initial baseline status alone prints nothing" {
	printf 's1\tWatching\t5\n' > "$IN"
	run cs_sync_notify_reader "s1=feat" < "$IN"
	assert_success
	assert_output ""
}

@test "notify: falls back to the session name when no label is given" {
	printf 's1\tWatching\t5\ns1\tScanning\t5\ns1\tWatching\t6\n' > "$IN"
	run cs_sync_notify_reader < "$IN"
	assert_success
	assert_output --partial "syncing s1"
	assert_output --partial "synced s1"
}

@test "notify: tracks multiple sessions independently" {
	printf 'a\tWatching\t1\nb\tWatching\t1\na\tScanning\t1\nb\tScanning\t1\na\tWatching\t2\nb\tWatching\t2\n' > "$IN"
	run cs_sync_notify_reader "a=repo-a" "b=repo-b" < "$IN"
	assert_success
	assert_output --partial "syncing repo-a"
	assert_output --partial "syncing repo-b"
	assert_output --partial "synced repo-a"
	assert_output --partial "synced repo-b"
}
