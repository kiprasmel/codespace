#!/usr/bin/env bats

# cs_sync_ignored_excludes builds an anchored rsync exclude list from the repo's
# gitignored paths plus the codespace control files.

load helpers

setup() {
	common_setup
	source_sync
}

@test "excludes: always anchors .git, open, .codespace/" {
	mkrepo "$SANDBOX/r"
	run cat "$(cs_sync_ignored_excludes "$SANDBOX/r")"
	assert_line '/.git'
	assert_line '/open'
	assert_line '/.codespace/'
}

@test "excludes: lists gitignored dirs and files (anchored), not tracked files" {
	mkrepo "$SANDBOX/r"
	cd "$SANDBOX/r"
	printf 'node_modules/\n*.log\n' > .gitignore
	git add .gitignore && git commit -q -m ignore
	mkdir -p node_modules/pkg && echo x > node_modules/pkg/index.js
	echo log > debug.log
	echo keep > tracked.txt && git add tracked.txt && git commit -q -m keep

	run cat "$(cs_sync_ignored_excludes "$SANDBOX/r")"
	assert_line '/node_modules/'
	assert_line '/debug.log'
	refute_line '/tracked.txt'
}
