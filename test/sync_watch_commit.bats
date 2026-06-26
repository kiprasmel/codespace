#!/usr/bin/env bats

# Phase 3: committing during a live session, including a PARTIAL commit.
# A commit (history) never travels via mutagen, so it must go through commit
# integration with the working tree frozen + the remainder preserved. This
# asserts the partial-commit case loses nothing: the committed subset syncs as
# history both ways; the uncommitted remainder survives on both ends.

load helpers

DEST="codespace/projects/myrepo_feat"

setup() {
	common_setup
	setup_local_remote
	install_mutagen_shim
	export CS_NO_EDIT=1

	git init -q --bare "$SANDBOX/origin.git"
	mkdir -p "$SANDBOX/projects"
	git clone -q "$SANDBOX/origin.git" "$SANDBOX/projects/myrepo" 2>/dev/null
	cd "$SANDBOX/projects/myrepo"
	git config user.email t@e.com && git config user.name t
	printf 'a\n' > f1.txt && printf 'b\n' > f2.txt && printf 'base\n' > shared.txt
	git add -A && git commit -q -m init
	git push -q origin master
	git branch feat
	git worktree add -q "$SANDBOX/projects/myrepo_feat" feat

	CS="$SANDBOX/projects/myrepo_feat"
	cd "$CS"
}

@test "commit-during-live: a partial commit integrates; the remainder survives both ends" {
	run codespace sync -r user@h --watch
	assert_success

	# mutagen would mirror the uncommitted tree; emulate identical dirty state
	# on both ends, then commit ONLY f1 locally (a partial commit).
	printf 'a-edited\n' > "$CS/f1.txt"
	printf 'b-edited\n' > "$CS/f2.txt"
	printf 'a-edited\n' > "$REMOTE_HOME/$DEST/f1.txt"
	printf 'b-edited\n' > "$REMOTE_HOME/$DEST/f2.txt"

	# disable the post-commit hook so its background sync can't race this one
	# (the lock serializes them in production; here we isolate the logic).
	rm -f "$(git -C "$CS" rev-parse --git-path hooks)/post-commit"
	git -C "$CS" add f1.txt && git -C "$CS" commit -q -m "commit f1 only"

	run codespace sync
	assert_success

	# the commit reached the remote (history synced both ways)
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	[ "$(remote_git "$DEST" log -1 --pretty=%s)" = "commit f1 only" ]
	[ "$(cat "$REMOTE_HOME/$DEST/f1.txt")" = "a-edited" ]

	# the uncommitted remainder (f2) survived on BOTH ends -- nothing lost
	[ "$(cat "$CS/f2.txt")" = "b-edited" ]
	[ "$(cat "$REMOTE_HOME/$DEST/f2.txt")" = "b-edited" ]

	# mutagen was frozen + resumed around the git history ops
	run grep -c 'sync pause' "$MUTAGEN_LOG"
	refute_output "0"
	run grep -c 'sync resume' "$MUTAGEN_LOG"
	refute_output "0"

	# still live afterwards
	run grep '^sync_mode=' "$CS/.codespace/sync"
	assert_output "sync_mode=live"
}

@test "first --watch: a diverged align preserves the remote's uncommitted remainder" {
	run codespace sync -r user@h            # provision the remote at base
	assert_success

	# diverge the histories AND leave the remote with an uncommitted edit to a
	# tracked file -- the kind an align reset --hard would silently revert.
	remote_git "$DEST" -c user.email=r@e -c user.name=r \
		commit -q --allow-empty -m "remote only"
	printf 'remote-wip\n' > "$REMOTE_HOME/$DEST/shared.txt"
	printf 'a2\n' > "$CS/f1.txt" && git -C "$CS" add f1.txt && git -C "$CS" commit -q -m "local 2"

	# the very first --watch (no session yet) must not lose shared.txt.
	# both sides advanced -> answer the integration prompt with [r]ebase.
	# clear the agent/CI env that codespace-utils uses to force non-interactive.
	run env CS_NO_INTERACTIVE= CURSOR_AGENT= CI= bash -c 'echo r | codespace sync --watch'
	assert_success

	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	run remote_git "$DEST" log --oneline
	assert_output --partial "remote only"
	[ "$(cat "$REMOTE_HOME/$DEST/shared.txt")" = "remote-wip" ]
}
