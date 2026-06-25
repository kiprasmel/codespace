#!/usr/bin/env bats

# Dirtiness probes (local + remote) against the local-remote harness.

load helpers

setup() {
	common_setup
	source_sync
	setup_local_remote
}

@test "local_dirty: false when clean, true with an untracked file" {
	mkrepo "$SANDBOX/r"
	run cs_sync_local_dirty "$SANDBOX/r"
	assert_failure
	echo untracked > "$SANDBOX/r/new.txt"
	run cs_sync_local_dirty "$SANDBOX/r"
	assert_success
}

@test "local_dirty: ignored files don't count" {
	mkrepo "$SANDBOX/r"
	cd "$SANDBOX/r"
	echo '*.log' > .gitignore
	git add .gitignore && git commit -q -m ignore
	echo noise > noise.log
	run cs_sync_local_dirty "$SANDBOX/r"
	assert_failure
}

@test "remote_dirty: false when clean, true when dirty" {
	# build a git repo at the remote dest
	local dest="codespace/org/repo_feat"
	mkdir -p "$REMOTE_HOME/$dest"
	( cd "$REMOTE_HOME/$dest" && HOME="$REMOTE_HOME" git init -q && \
		HOME="$REMOTE_HOME" git commit -q --allow-empty -m init )

	run cs_sync_remote_dirty "user@h" "$dest"
	assert_failure

	echo change > "$REMOTE_HOME/$dest/f.txt"
	run cs_sync_remote_dirty "user@h" "$dest"
	assert_success
}
