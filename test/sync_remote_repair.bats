#!/usr/bin/env bats

# cs_sync_remote_health + cs_sync_remote_repair, exercised over the local-remote
# ssh shim so the real declare-f / ssh / git-worktree path runs.
#
# Repair heals a half-provisioned remote WITHOUT losing work:
#   - base repo present -> re-link the worktree in place (no files moved)
#   - base repo gone    -> archive the dir aside (mv, never rm), then reprovision

load helpers

setup() {
	common_setup
	source_sync
	setup_local_remote
}

# base repo + a worktree checkout on branch `feat`, with a committed file and an
# untracked file in the worktree. Args: base_rel dest_rel
mk_remote_worktree() {
	local base="$REMOTE_HOME/$1" dest="$REMOTE_HOME/$2"
	HOME="$REMOTE_HOME" git init -q -b master "$base"
	HOME="$REMOTE_HOME" git -C "$base" commit --allow-empty -q -m init
	HOME="$REMOTE_HOME" git -C "$base" worktree add -q -b feat "$dest" >/dev/null
	echo tracked  > "$dest/tracked.txt"
	HOME="$REMOTE_HOME" git -C "$dest" add tracked.txt
	HOME="$REMOTE_HOME" git -C "$dest" commit -q -m tracked
	echo WIP > "$dest/untracked.txt"
}

@test "remote_health: ok for a healthy worktree" {
	mk_remote_worktree codespace/org/repo codespace/org/repo_feat
	run cs_sync_remote_health host codespace/org/repo_feat codespace/org/repo worktree
	assert_success
	assert_output ok
}

@test "remote_health: absent when nothing is there" {
	run cs_sync_remote_health host codespace/org/nope codespace/org/base worktree
	assert_success
	assert_output absent
}

@test "remote_health: broken when the base repo is gone" {
	mk_remote_worktree codespace/org/repo codespace/org/repo_feat
	rm -rf "$REMOTE_HOME/codespace/org/repo"
	run cs_sync_remote_health host codespace/org/repo_feat codespace/org/repo worktree
	assert_success
	assert_output broken
}

@test "remote_repair: base gone -> archives dir aside (mv), preserving work" {
	mk_remote_worktree codespace/org/repo codespace/org/repo_feat
	rm -rf "$REMOTE_HOME/codespace/org/repo"

	run cs_sync_remote_repair host codespace/org/repo_feat codespace/org/repo worktree
	assert_success
	assert_output --partial archived

	# dest moved aside, not deleted; both tracked + untracked survive.
	assert [ ! -e "$REMOTE_HOME/codespace/org/repo_feat" ]
	local arch
	arch="$(echo "$REMOTE_HOME"/codespace/org/repo_feat.broken-*)"
	assert [ -d "$arch" ]
	assert [ -f "$arch/tracked.txt" ]
	assert [ -f "$arch/untracked.txt" ]
}

@test "remote_repair: base present but link stale -> repaired in place, nothing moved" {
	# build the worktree against a scratch base, then move the base to its real
	# path: the worktree's .git now points at a stale location (broken), but the
	# base repo is valid -- exactly the case `git worktree repair` fixes.
	mk_remote_worktree codespace/org/tmpbase codespace/org/repo_feat
	mv "$REMOTE_HOME/codespace/org/tmpbase" "$REMOTE_HOME/codespace/org/repo"

	run cs_sync_remote_health host codespace/org/repo_feat codespace/org/repo worktree
	assert_output broken

	run cs_sync_remote_repair host codespace/org/repo_feat codespace/org/repo worktree
	assert_success
	assert_output --partial repaired

	# healed in place: dir + files untouched, no archive created, now healthy.
	assert [ -f "$REMOTE_HOME/codespace/org/repo_feat/untracked.txt" ]
	run bash -c "ls -d '$REMOTE_HOME'/codespace/org/repo_feat.broken-* 2>/dev/null || true"
	assert_output ""
	run cs_sync_remote_health host codespace/org/repo_feat codespace/org/repo worktree
	assert_output ok
}
