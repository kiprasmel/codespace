#!/usr/bin/env bats

# End-to-end `codespace sync` against a "local remote" (ssh/rsync shims that
# operate on a local $REMOTE_HOME). Exercises real commit transfer + the
# provision / fast-forward / diverged-rebase / force / overlay paths.

load helpers

DEST="codespace/projects/myrepo_feat"

setup() {
	common_setup
	setup_local_remote
	export CS_NO_EDIT=1

	# bare origin + base repo clone (so provisioning can infer the clone URL).
	git init -q --bare "$SANDBOX/origin.git"
	mkdir -p "$SANDBOX/projects"
	git clone -q "$SANDBOX/origin.git" "$SANDBOX/projects/myrepo" 2>/dev/null
	cd "$SANDBOX/projects/myrepo"
	git config user.email t@e.com
	git config user.name t
	echo hello > file.txt
	git add -A && git commit -q -m init
	git push -q origin master
	git branch feat
	git worktree add -q "$SANDBOX/projects/myrepo_feat" feat

	CS="$SANDBOX/projects/myrepo_feat"
	cd "$CS"
}

@test "e2e: first sync provisions the remote and aligns it to local HEAD" {
	echo change >> file.txt
	git add -A && git commit -q -m "local 1"

	run codespace sync -r user@h
	assert_success

	[ -e "$REMOTE_HOME/$DEST/.git" ]
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]

	run grep '^host=' "$CS/.codespace/sync"
	assert_output "host=user@h"
}

@test "e2e: re-sync remembers the host from the marker (no -r needed)" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	echo b >> file.txt && git add -A && git commit -q -m "local 2"
	run codespace sync
	assert_success

	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
}

@test "e2e: both sides advanced + non-interactive aborts (no silent rewrite)" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	# remote produces its own commit AND local advances -> genuinely ambiguous
	remote_git "$DEST" -c user.email=r@e -c user.name=r \
		commit -q --allow-empty -m "remote only"
	echo b >> file.txt && git add -A && git commit -q -m "local 2"
	local lbefore rbefore
	lbefore="$(git -C "$CS" rev-parse HEAD)"
	rbefore="$(remote_git "$DEST" rev-parse HEAD)"

	run codespace sync
	assert_failure
	assert_output --partial "both sides advanced"

	# nothing was rewritten on either side
	[ "$(git -C "$CS" rev-parse HEAD)" = "$lbefore" ]
	[ "$(remote_git "$DEST" rev-parse HEAD)" = "$rbefore" ]
}

@test "e2e: both sides advanced + interactive [r]ebase converges" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	remote_git "$DEST" -c user.email=r@e -c user.name=r \
		commit -q --allow-empty -m "remote only"
	echo b >> file.txt && git add -A && git commit -q -m "local 2"

	# answer the [r]ebase/[o]urs/[t]heirs/[a]bort prompt with rebase (default).
	# clear the agent/CI env that codespace-utils uses to force non-interactive.
	run env CS_NO_INTERACTIVE= CURSOR_AGENT= CI= bash -c 'echo r | codespace sync'
	assert_success

	# both ends converge to the same history, including the remote's commit
	local llog rlog
	llog="$(git -C "$CS" log --oneline | sed 's/^[0-9a-f]* //')"
	rlog="$(remote_git "$DEST" log --oneline | sed 's/^[0-9a-f]* //')"
	[ "$llog" = "$rlog" ]
	[[ "$llog" == *"remote only"* ]]
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
}

@test "e2e: --ours makes the remote match local HEAD and backs up its old tip" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	remote_git "$DEST" -c user.email=r@e -c user.name=r \
		commit -q --allow-empty -m "remote only"
	echo b >> file.txt && git add -A && git commit -q -m "local 2"

	run codespace sync --ours
	assert_success

	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	run remote_git "$DEST" log --oneline
	refute_output --partial "remote only"
	run remote_git "$DEST" for-each-ref refs/cs-sync/backup
	assert_output --partial "refs/cs-sync/backup/feat/"
}

@test "e2e: --theirs resets local to the remote tip and backs up the local tip" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	remote_git "$DEST" -c user.email=r@e -c user.name=r \
		commit -q --allow-empty -m "remote only"
	echo b >> file.txt && git add -A && git commit -q -m "local 2"

	run codespace sync --theirs
	assert_success

	# local now matches the remote tip; the local-only commit is gone from HEAD
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	run git -C "$CS" log --oneline
	assert_output --partial "remote only"
	refute_output --partial "local 2"
	run git -C "$CS" for-each-ref refs/cs-sync/backup/local
	assert_output --partial "refs/cs-sync/backup/local/feat/"
}

@test "e2e: amending an already-synced commit stays one commit (local wins)" {
	echo foo > tmp.txt && git add -A && git commit -q -m "add tmp"
	run codespace sync -r user@h
	assert_success

	# rewrite the already-synced commit; the remote has not moved
	echo bar >> tmp.txt && git add -A && git commit -q --amend --no-edit
	run codespace sync
	assert_success

	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	run bash -c "git -C '$CS' log --oneline | grep -c 'add tmp'"
	assert_output "1"
	grep -q foo "$REMOTE_HOME/$DEST/tmp.txt"
	grep -q bar "$REMOTE_HOME/$DEST/tmp.txt"
	run remote_git "$DEST" for-each-ref refs/cs-sync/backup/feat
	assert_output --partial "refs/cs-sync/backup/feat/"
}

@test "e2e: squashing already-synced commits stays one commit (local wins)" {
	echo 1 > a.txt && git add -A && git commit -q -m "first"
	echo 2 > b.txt && git add -A && git commit -q -m "second"
	run codespace sync -r user@h
	assert_success

	# squash both into one; the remote has not moved
	git reset -q --soft HEAD~2 && git commit -q -m "squashed"
	run codespace sync
	assert_success

	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	run remote_git "$DEST" log --oneline
	assert_output --partial "squashed"
	refute_output --partial "first"
	refute_output --partial "second"
	# the squashed content is intact on the remote
	[ -f "$REMOTE_HOME/$DEST/a.txt" ]
	[ -f "$REMOTE_HOME/$DEST/b.txt" ]
}

@test "e2e: default (mode=dirty) overlays uncommitted work to a clean remote" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	echo dirtyline >> file.txt
	run codespace sync
	assert_success
	grep -q dirtyline "$REMOTE_HOME/$DEST/file.txt"
}

@test "e2e: uncommitted on both sides refuses the overlay (non-interactive)" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	# dirty the local tree AND the remote working tree -> a one-shot overlay
	# would clobber the remote's uncommitted edit, so it must refuse.
	echo localdirty >> file.txt
	echo remotedirty >> "$REMOTE_HOME/$DEST/file.txt"
	run codespace sync
	assert_failure
	assert_output --partial "refusing a one-shot overlay"
}

@test "e2e: --once overlays the working tree honoring gitignore" {
	printf 'ignored/\n*.log\n' > .gitignore
	git add -A && git commit -q -m gitignore
	run codespace sync -r user@h
	assert_success

	echo dirtycontent >> file.txt           # tracked, modified -> ship
	echo fresh > untracked.txt              # untracked, not ignored -> ship
	mkdir -p ignored && echo big > ignored/blob.bin   # ignored dir -> skip
	echo noise > noise.log                  # ignored file -> skip

	run codespace sync --once
	assert_success

	grep -q dirtycontent "$REMOTE_HOME/$DEST/file.txt"
	[ -f "$REMOTE_HOME/$DEST/untracked.txt" ]
	[ ! -e "$REMOTE_HOME/$DEST/ignored" ]
	[ ! -e "$REMOTE_HOME/$DEST/noise.log" ]
}

@test "e2e: --mode=commits syncs history only, leaving the dirty tree local" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	echo wip >> file.txt                    # uncommitted; must stay local-only
	run codespace sync --mode=commits
	assert_success

	# the remote never received the uncommitted edit ...
	run grep -c wip "$REMOTE_HOME/$DEST/file.txt"
	assert_output "0"
	# ... and it's still present locally.
	[ -n "$(git status --porcelain)" ]
}

@test "e2e: invalid --mode is rejected" {
	run codespace sync -r user@h --mode bogus
	assert_failure
	assert_output --partial "--mode must be 'dirty' (d) or 'commits' (c)"
}

@test "e2e: -m and the d/c mode aliases are accepted" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	echo wip >> file.txt                    # uncommitted
	run codespace sync -m c                 # 'c' == commits -> history only
	assert_success
	run grep -c wip "$REMOTE_HOME/$DEST/file.txt"
	assert_output "0"

	run codespace sync --mode=d             # 'd' == dirty -> overlays the tree
	assert_success
	grep -q wip "$REMOTE_HOME/$DEST/file.txt"
}

@test "e2e: --dry-run mutates nothing" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h --dry-run
	assert_success
	[ ! -e "$REMOTE_HOME/$DEST" ]
	[ ! -f "$CS/.codespace/sync" ]
}
