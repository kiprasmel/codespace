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

@test "e2e: diverged histories rebase locally then the remote converges" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	# remote produces its own commit (independent -> no conflict)
	remote_git "$DEST" -c user.email=r@e -c user.name=r \
		commit -q --allow-empty -m "remote only"
	echo b >> file.txt && git add -A && git commit -q -m "local 2"

	run codespace sync
	assert_success

	# both ends converge to the same history, including the remote's commit
	local llog rlog
	llog="$(git -C "$CS" log --oneline | sed 's/^[0-9a-f]* //')"
	rlog="$(remote_git "$DEST" log --oneline | sed 's/^[0-9a-f]* //')"
	[ "$llog" = "$rlog" ]
	[[ "$llog" == *"remote only"* ]]
	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
}

@test "e2e: --force makes the remote match local HEAD and backs up its old tip" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	remote_git "$DEST" -c user.email=r@e -c user.name=r \
		commit -q --allow-empty -m "remote only"
	echo b >> file.txt && git add -A && git commit -q -m "local 2"

	run codespace sync --force
	assert_success

	[ "$(git -C "$CS" rev-parse HEAD)" = "$(remote_git "$DEST" rev-parse HEAD)" ]
	run remote_git "$DEST" log --oneline
	refute_output --partial "remote only"
	run remote_git "$DEST" for-each-ref refs/cs-sync/backup
	assert_output --partial "refs/cs-sync/backup/feat/"
}

@test "e2e: uncommitted + non-interactive (no flag) aborts" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h
	assert_success

	echo dirty >> file.txt
	run codespace sync
	assert_failure
	assert_output --partial "uncommitted changes present"
}

@test "e2e: --uncommitted --once overlays the working tree honoring gitignore" {
	printf 'ignored/\n*.log\n' > .gitignore
	git add -A && git commit -q -m gitignore
	run codespace sync -r user@h
	assert_success

	echo dirtycontent >> file.txt           # tracked, modified -> ship
	echo fresh > untracked.txt              # untracked, not ignored -> ship
	mkdir -p ignored && echo big > ignored/blob.bin   # ignored dir -> skip
	echo noise > noise.log                  # ignored file -> skip

	run codespace sync --uncommitted --once
	assert_success

	grep -q dirtycontent "$REMOTE_HOME/$DEST/file.txt"
	[ -f "$REMOTE_HOME/$DEST/untracked.txt" ]
	[ ! -e "$REMOTE_HOME/$DEST/ignored" ]
	[ ! -e "$REMOTE_HOME/$DEST/noise.log" ]
}

@test "e2e: --commit commits local changes then integrates" {
	run codespace sync -r user@h
	assert_success

	echo new > new.txt
	run codespace sync --commit -m "wip add"
	assert_success

	[ "$(remote_git "$DEST" log -1 --pretty=%s)" = "wip add" ]
	run remote_git "$DEST" status --porcelain
	assert_output ""
}

@test "e2e: --dry-run mutates nothing" {
	echo a >> file.txt && git add -A && git commit -q -m "local 1"
	run codespace sync -r user@h --dry-run
	assert_success
	[ ! -e "$REMOTE_HOME/$DEST" ]
	[ ! -f "$CS/.codespace/sync" ]
}
