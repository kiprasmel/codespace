#!/usr/bin/env bats

# A failed remote align (the remote isn't a healthy codespace) must abort the
# repo's sync with a non-zero status BEFORE starting a watch / shipping files /
# writing a marker -- i.e. never report a false "synced" over a broken remote.

load helpers

setup() {
	common_setup
	source_sync

	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"

	# neutralize everything up to align so nothing hits the network.
	cs_sync_migrate_purge_hooks() { :; }
	cs_ensure_agent_key() { :; }
	cs_sync_remote_health() { echo ok; }          # remote already provisioned
	cs_sync_remote_exists() { return 0; }
	cs_sync_local_dirty() { return 1; }           # clean on both ends
	cs_sync_remote_dirty() { return 1; }
	cs_sync_resolve_uncommitted() { echo watch; }
	cs_sync_watch_active() { return 1; }          # no live session running
	cs_sync_remote_stash_push() { return 1; }
	cs_sync_marker_get() { echo ""; }
	cs_sync_integrate_local() { echo ""; }        # nothing to integrate, ok
	cs_sync_watch_resolve_conflicts() { :; }

	# sentinels for steps that must NOT run once align fails.
	SHIP_RAN="$BATS_TEST_TMPDIR/ship.ran"
	MARKER_RAN="$BATS_TEST_TMPDIR/marker.ran"
	WATCH_RAN="$BATS_TEST_TMPDIR/watch.ran"
	cs_collect_remote_files() { echo "$BATS_TEST_TMPDIR/manifest"; : > "$BATS_TEST_TMPDIR/manifest"; }
	cs_ship_files_to_remote() { touch "$SHIP_RAN"; }
	cs_sync_marker_write() { touch "$MARKER_RAN"; }
	cs_sync_watch_start() { touch "$WATCH_RAN"; }
}

@test "sync_repo: align failure -> non-zero, skips watch/ship/marker" {
	cs_sync_align_remote() { return 1; }

	cd "$REPO"
	run cs_sync_repo "$REPO" host dirty 1 "" ""
	assert_failure
	assert [ ! -f "$WATCH_RAN" ]
	assert [ ! -f "$SHIP_RAN" ]
	assert [ ! -f "$MARKER_RAN" ]
}

@test "sync_repo: align success -> starts watch, ships, writes marker" {
	cs_sync_align_remote() { return 0; }

	cd "$REPO"
	run cs_sync_repo "$REPO" host dirty 1 "" ""
	assert_success
	assert [ -f "$WATCH_RAN" ]
	assert [ -f "$SHIP_RAN" ]
	assert [ -f "$MARKER_RAN" ]
}
