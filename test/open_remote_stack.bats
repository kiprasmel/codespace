#!/usr/bin/env bats

# `codespace open -r` inside a stack: repo vs stack scope resolution, scope-change
# watch restart, and the watch-already-running stop hint.

load helpers

setup() {
	common_setup
	setup_local_remote
	install_mutagen_shim
	export CS_NO_EDIT=1
	export CS_WATCH_POLL_MAX=0

	mkdir -p "$SANDBOX/myorg"
	_mkrepo_origin repo-a
	_mkrepo_origin repo-b

	STACK="$SANDBOX/myorg/stack_feat"
	mkdir -p "$STACK"
	git -C "$SANDBOX/myorg/repo-a" worktree add -q "$STACK/repo-a" feat
	git -C "$SANDBOX/myorg/repo-b" worktree add -q "$STACK/repo-b" feat
}

_mkrepo_origin() {
	local name="$1"
	git init -q --bare "$SANDBOX/$name.git"
	git clone -q "$SANDBOX/$name.git" "$SANDBOX/myorg/$name" 2>/dev/null
	(
		cd "$SANDBOX/myorg/$name"
		git config user.email t@e.com && git config user.name t
		echo "$name" > f.txt
		git add -A && git commit -q -m init
		git push -q origin master
		git branch feat
	)
}

_srdir() { echo "$REMOTE_HOME/codespace/myorg/stack_feat/$1"; }

_stop_all_watches() {
	local pid d
	for d in "$STACK" "$STACK/repo-a" "$STACK/repo-b"; do
		pid="$(grep '^watch_pid=' "$d/.codespace/sync" 2>/dev/null | cut -d= -f2)" || pid=""
		[ -n "$pid" ] && kill "$pid" 2>/dev/null || true
	done
}

teardown() {
	_stop_all_watches
	common_teardown
}

@test "open -r from stack repo: CS_NO_INTERACTIVE syncs the entire stack" {
	cd "$STACK/repo-a"
	run codespace open -r user@h
	assert_success
	assert_output --partial "$STACK"

	[ -e "$(_srdir repo-a)/.git" ]
	[ -e "$(_srdir repo-b)/.git" ]
	run grep '^kind=' "$STACK/.codespace/sync"
	assert_output "kind=stack"
}

@test "open -r from stack repo: interactive choice 2 syncs the entire stack" {
	force_interactive
	cd "$STACK/repo-a"
	printf '2\n' | script -q /dev/null codespace open -r user@h

	[ -e "$(_srdir repo-a)/.git" ]
	[ -e "$(_srdir repo-b)/.git" ]
	run grep '^kind=' "$STACK/.codespace/sync"
	assert_output "kind=stack"
}

@test "open -r: explicit stack repo path syncs this repo only" {
	cd "$STACK/repo-a"
	run codespace open -r user@h "$STACK/repo-a"
	assert_success

	[ -e "$(_srdir repo-a)/.git" ]
	[ ! -e "$(_srdir repo-b)/.git" ]
	[ -f "$STACK/repo-a/.codespace/sync" ]
	[ ! -f "$STACK/.codespace/sync" ]
}

@test "open -r: repo-only watch then stack root restarts at stack scope" {
	cd "$STACK/repo-a"
	run codespace open -r user@h "$STACK/repo-a"
	assert_success
	[ -f "$STACK/repo-a/.codespace/sync" ]
	[ ! -f "$STACK/.codespace/sync" ]

	cd "$STACK"
	run codespace open -r
	assert_success
	assert_output --partial "$STACK"
	refute_output --partial "watch is already running"

	[ -e "$(_srdir repo-b)/.git" ]
	run grep '^kind=' "$STACK/.codespace/sync"
	assert_output "kind=stack"
	run grep -c '^mutagen_session=' "$STACK/repo-a/.codespace/sync"
	assert_output "1"
	run grep -c '^mutagen_session=' "$STACK/repo-b/.codespace/sync"
	assert_output "1"
}

@test "open -r: second open at same scope prints stop hint" {
	cd "$STACK/repo-a"
	run codespace open -r user@h
	assert_success

	run codespace open -r
	assert_success
	assert_output --partial "watch is already running"
	assert_output --partial "codespace sync --stop"
}
