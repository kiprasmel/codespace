#!/usr/bin/env bats

# Migration off the legacy post-commit hooks. Older versions installed a tagged
# `post-commit` hook on both ends to trigger commit syncs; the HEAD poll loop
# replaced them. A plain sync now detects + removes any stale (tagged) hook
# (restoring a pre-existing hook it had backed up as .precs), on both ends.

load helpers

DEST="codespace/projects/myrepo_feat"
TAG="# codespace-sync live-sync trigger"

setup() {
	common_setup
	setup_local_remote
	export CS_NO_EDIT=1

	git init -q --bare "$SANDBOX/origin.git"
	mkdir -p "$SANDBOX/projects"
	git clone -q "$SANDBOX/origin.git" "$SANDBOX/projects/myrepo" 2>/dev/null
	cd "$SANDBOX/projects/myrepo"
	git config user.email t@e.com && git config user.name t
	echo hello > file.txt
	git add -A && git commit -q -m init
	git push -q origin master
	git branch feat
	git worktree add -q "$SANDBOX/projects/myrepo_feat" feat

	CS="$SANDBOX/projects/myrepo_feat"
	cd "$CS"
}

_local_hook()  { echo "$(git -C "$CS" rev-parse --git-path hooks)/post-commit"; }
_remote_hook() { echo "$(remote_git "$DEST" rev-parse --git-path hooks)/post-commit"; }

# Plant a benign hook carrying our tag at $1 (the migration keys on the tag, not
# the body, so we avoid the real self-invoking body to keep the test inert).
_plant_stale_hook() {
	mkdir -p "$(dirname "$1")"
	printf '#!/usr/bin/env bash\n%s\nexit 0\n' "$TAG" > "$1"
	chmod +x "$1"
}

@test "migrate: a stale local post-commit hook is removed on the next sync" {
	local hook; hook="$(_local_hook)"
	_plant_stale_hook "$hook"
	[ -f "$hook" ]

	run codespace sync -r user@h
	assert_success
	assert_output --partial "stale codespace-sync post-commit hook"

	[ ! -f "$hook" ]
}

@test "migrate: a backed-up pre-existing hook (.precs) is restored" {
	local hook; hook="$(_local_hook)"
	_plant_stale_hook "$hook"
	printf '#!/usr/bin/env bash\necho mine\n' > "$hook.precs"

	run codespace sync -r user@h
	assert_success

	# ours removed, the user's original hook is back in place
	[ -f "$hook" ]
	run grep -qF "$TAG" "$hook"
	assert_failure
	run cat "$hook"
	assert_output --partial "echo mine"
	[ ! -f "$hook.precs" ]
}

@test "migrate: the remote's stale hook is purged too" {
	# first sync provisions the remote worktree.
	run codespace sync -r user@h
	assert_success

	# now both ends carry a stale hook (as an older --watch would have left them).
	local lhook rhook; lhook="$(_local_hook)"; rhook="$(_remote_hook)"
	_plant_stale_hook "$lhook"
	_plant_stale_hook "$rhook"
	[ -f "$rhook" ]

	run codespace sync
	assert_success

	[ ! -f "$lhook" ]
	[ ! -f "$rhook" ]
}

@test "migrate: a foreign (untagged) post-commit hook is left untouched" {
	local hook; hook="$(_local_hook)"
	mkdir -p "$(dirname "$hook")"
	printf '#!/usr/bin/env bash\necho not-ours\n' > "$hook"
	chmod +x "$hook"

	run codespace sync -r user@h
	assert_success
	refute_output --partial "stale codespace-sync post-commit hook"

	[ -f "$hook" ]
	run cat "$hook"
	assert_output --partial "echo not-ours"
}
