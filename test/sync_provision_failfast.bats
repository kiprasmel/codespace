#!/usr/bin/env bats

# A failed remote provision (e.g. the base clone couldn't authenticate) must
# abort the repo's sync with a non-zero status, NOT cascade into ship / bootstrap
# / post-create / align / watch against a path that was never created.

load helpers

setup() {
	common_setup
	source_sync

	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"

	# neutralize host-touching + local-agent helpers so nothing hits the network.
	cs_ensure_agent_key() { :; }
	cs_remote_self_install() { :; }
	cs_remote_probe() { :; }
	cs_rsync_config_to_remote() { echo "codespace-config/$2"; }
	cs_collect_remote_files() { echo "$BATS_TEST_TMPDIR/manifest"; : > "$BATS_TEST_TMPDIR/manifest"; }
	cs_ship_files_to_remote() { :; }

	# sentinels for steps that must NOT run once provisioning fails.
	BOOTSTRAP_RAN="$BATS_TEST_TMPDIR/bootstrap.ran"
	POSTCREATE_RAN="$BATS_TEST_TMPDIR/postcreate.ran"
	cs_remote_run_bootstrap() { touch "$BOOTSTRAP_RAN"; }
	cs_remote_run_post_create() { touch "$POSTCREATE_RAN"; }
}

@test "sync_provision: worktree core failure -> non-zero, skips bootstrap/post-create" {
	cs_create_remote_worktree_core() { return 1; }

	run cs_sync_provision host org/myrepo br codespace/org/myrepo_br worktree codespace/org/myrepo "$REPO"
	assert_failure
	assert [ ! -f "$BOOTSTRAP_RAN" ]
	assert [ ! -f "$POSTCREATE_RAN" ]
}

@test "sync_provision: clone core failure -> non-zero, skips bootstrap/post-create" {
	cs_create_remote_clone_core() { return 1; }

	run cs_sync_provision host org/myrepo br codespace/org/myrepo_br clone codespace/org/myrepo_br "$REPO"
	assert_failure
	assert [ ! -f "$BOOTSTRAP_RAN" ]
	assert [ ! -f "$POSTCREATE_RAN" ]
}

@test "sync_repo: provision failure aborts before align/integrate" {
	cs_sync_migrate_purge_hooks() { :; }
	cs_sync_remote_health() { echo absent; } # remote absent -> provision attempted
	cs_sync_remote_exists() { return 1; }
	cs_sync_provision() { return 1; }        # ...and it fails

	ALIGN_RAN="$BATS_TEST_TMPDIR/align.ran"
	INTEGRATE_RAN="$BATS_TEST_TMPDIR/integrate.ran"
	cs_sync_align_remote() { touch "$ALIGN_RAN"; }
	cs_sync_integrate_local() { touch "$INTEGRATE_RAN"; echo ff; }

	cd "$REPO"
	run cs_sync_repo "$REPO" host dirty "" "" ""
	assert_failure
	assert [ ! -f "$ALIGN_RAN" ]
	assert [ ! -f "$INTEGRATE_RAN" ]
}
