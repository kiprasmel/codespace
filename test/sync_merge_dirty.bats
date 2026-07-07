#!/usr/bin/env bats

# cs_sync_merge_dirty: granular 3-way content merge of uncommitted work.
# Exercises the shared primitive directly (local-remote harness) and one-shot e2e.

load helpers

DEST="codespace/projects/myrepo_feat"

setup() {
	common_setup
	source_sync
	setup_local_remote
	export CS_NO_EDIT=1

	git init -q --bare "$SANDBOX/origin.git"
	mkdir -p "$SANDBOX/projects"
	git clone -q "$SANDBOX/origin.git" "$SANDBOX/projects/myrepo" 2>/dev/null
	cd "$SANDBOX/projects/myrepo"
	git config user.email t@e.com
	git config user.name t
	printf 'L1\nL2\nL3\nL4\n' > shared.txt
	printf 'only-local\n' > local.txt
	git add -A && git commit -q -m init
	git push -q origin master
	git branch feat
	git worktree add -q "$SANDBOX/projects/myrepo_feat" feat

	CS="$SANDBOX/projects/myrepo_feat"
	cd "$CS"
	run codespace sync -r user@h
	assert_success
}

# Both sides dirty at the same HEAD; merge locally then mirror to remote.
merge_both_dirty() {
	local resolve="${1:-}" hard="${2:-}"
	local local_dirty="" remote_dirty="" tree
	cs_sync_local_dirty "$CS" && local_dirty=1
	cs_sync_remote_dirty user@h "$DEST" && remote_dirty=1
	tree="$(cs_sync_merge_dirty user@h "$DEST" "$CS" feat "$resolve" "$hard" \
		"$local_dirty" "$remote_dirty")"
	cs_sync_overlay user@h "$DEST" "$CS"
	printf '%s' "$tree"
}

@test "merge_dirty: different files on each side -> both kept locally" {
	printf 'local-edit\n' > local.txt
	printf 'remote-edit\n' > "$REMOTE_HOME/$DEST/remote.txt"

	merge_both_dirty >/dev/null

	[ "$(cat "$CS/local.txt")" = "local-edit" ]
	[ "$(cat "$CS/remote.txt")" = "remote-edit" ]
}

@test "merge_dirty: same file, different hunks -> both kept, no markers" {
	printf 'L1-local\nL2\nL3\nL4\n' > shared.txt
	printf 'L1\nL2\nL3\nL4-remote\n' > "$REMOTE_HOME/$DEST/shared.txt"

	merge_both_dirty >/dev/null

	grep -q 'L1-local' "$CS/shared.txt"
	grep -q 'L4-remote' "$CS/shared.txt"
	refute grep -q '^<<<<<<< ' "$CS/shared.txt"
}

@test "merge_dirty: same hunk clash -> identical markers on both sides" {
	printf 'CLASH\n' > shared.txt
	printf 'CLASH-REMOTE\n' > "$REMOTE_HOME/$DEST/shared.txt"

	merge_both_dirty >/dev/null

	grep -q '^<<<<<<< ' "$CS/shared.txt"
	grep -q '^<<<<<<< ' "$REMOTE_HOME/$DEST/shared.txt"
	[ "$(cat "$CS/shared.txt")" = "$(cat "$REMOTE_HOME/$DEST/shared.txt")" ]
}

@test "merge_dirty: same hunk + --ours -> local wins" {
	printf 'CLASH\n' > shared.txt
	printf 'CLASH-REMOTE\n' > "$REMOTE_HOME/$DEST/shared.txt"

	merge_both_dirty ours >/dev/null

	[ "$(cat "$CS/shared.txt")" = "CLASH" ]
	[ "$(cat "$REMOTE_HOME/$DEST/shared.txt")" = "CLASH" ]
}

@test "merge_dirty: same hunk + --theirs -> remote wins" {
	printf 'CLASH\n' > shared.txt
	printf 'CLASH-REMOTE\n' > "$REMOTE_HOME/$DEST/shared.txt"

	merge_both_dirty theirs >/dev/null

	[ "$(cat "$CS/shared.txt")" = "CLASH-REMOTE" ]
}

@test "merge_dirty: synced_dirty checkpoint converges after one-sided resolution" {
	printf 'CLASH\n' > shared.txt
	printf 'CLASH-REMOTE\n' > "$REMOTE_HOME/$DEST/shared.txt"

	local tree markers head local_dirty="" remote_dirty=""
	head="$(git -C "$CS" rev-parse HEAD)"
	cs_sync_local_dirty "$CS" && local_dirty=1
	cs_sync_remote_dirty user@h "$DEST" && remote_dirty=1
	tree="$(cs_sync_merge_dirty user@h "$DEST" "$CS" feat "" "" \
		"$local_dirty" "$remote_dirty")"
	markers="$(cs_sync_dirty_merged_markers "$CS" "$tree")"
	cs_sync_overlay user@h "$DEST" "$CS"
	cs_sync_dirty_record_synced "$CS" "$head" "$tree" "$markers"

	printf 'RESOLVED\n' > "$CS/shared.txt"
	cs_sync_local_dirty "$CS" && local_dirty=1
	cs_sync_remote_dirty user@h "$DEST" && remote_dirty=1
	[ "$(cs_sync_dirty_merge_base "$CS" "$head")" != "$head" ]

	tree="$(cs_sync_merge_dirty user@h "$DEST" "$CS" feat "" "" \
		"$local_dirty" "$remote_dirty")"
	cs_sync_overlay user@h "$DEST" "$CS"

	[ "$(cat "$CS/shared.txt")" = "RESOLVED" ]
	[ "$(cat "$REMOTE_HOME/$DEST/shared.txt")" = "RESOLVED" ]
	refute grep -q '^<<<<<<< ' "$CS/shared.txt"
}

@test "e2e merge: both sides dirty one-shot sync succeeds (non-fatal markers)" {
	printf 'local\n' > local.txt
	printf 'remote\n' > "$REMOTE_HOME/$DEST/remote.txt"
	printf 'X\n' > shared.txt
	printf 'Y\n' > "$REMOTE_HOME/$DEST/shared.txt"

	run codespace sync
	assert_success
	assert_output --partial "conflict marker"

	[ "$(cat "$CS/local.txt")" = "local" ]
	[ "$(cat "$CS/remote.txt")" = "remote" ]
	[ "$(cat "$CS/shared.txt")" = "$(cat "$REMOTE_HOME/$DEST/shared.txt")" ]
}

@test "e2e merge: remote-only dirty is taken locally" {
	printf 'remote-wip\n' > "$REMOTE_HOME/$DEST/shared.txt"

	run codespace sync
	assert_success

	[ "$(cat "$CS/shared.txt")" = "remote-wip" ]
	[ "$(cat "$REMOTE_HOME/$DEST/shared.txt")" = "remote-wip" ]
}
