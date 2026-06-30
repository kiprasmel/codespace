#!/usr/bin/env bats

# Pure decision over (dirty flags, mode, live, ...) -> action token.
# Args: local_dirty remote_dirty sync_mode live once interactive mutagen_ok
# Tokens: proceed | overlay | watch | prompt | abort

load helpers

setup() {
	common_setup
	source_sync
}

# --- mode=commits: never touch the working tree -----------------------------

@test "decide: mode=commits, clean -> proceed" {
	run cs_sync_decide_uncommitted "" "" commits "" "" 1 ""
	assert_output proceed
}

@test "decide: mode=commits leaves local dirty alone -> proceed" {
	run cs_sync_decide_uncommitted 1 "" commits "" "" 1 ""
	assert_output proceed
}

@test "decide: mode=commits with both sides dirty -> proceed" {
	run cs_sync_decide_uncommitted 1 1 commits "" "" 1 1
	assert_output proceed
}

# --- --watch (live) always engages, even on a clean tree --------------------

@test "decide: live with mutagen present starts a session even when clean" {
	run cs_sync_decide_uncommitted "" "" dirty 1 "" 1 1
	assert_output watch
}

@test "decide: live on a clean tree without mutagen -> watch (engage anyway)" {
	run cs_sync_decide_uncommitted "" "" dirty 1 "" 1 ""
	assert_output watch
}

@test "decide: live always -> watch (clean, non-interactive, no mutagen)" {
	run cs_sync_decide_uncommitted "" "" dirty 1 "" "" ""
	assert_output watch
}

@test "decide: live on a dirty tree without mutagen -> watch (offer install)" {
	run cs_sync_decide_uncommitted 1 "" dirty 1 "" 1 ""
	assert_output watch
}

@test "decide: live wins when both dirty" {
	run cs_sync_decide_uncommitted 1 1 dirty 1 "" 1 1
	assert_output watch
}

# --- mode=dirty, no --watch: clean short-circuits ---------------------------

@test "decide: mode=dirty, both clean, no watch -> proceed" {
	run cs_sync_decide_uncommitted "" "" dirty "" "" 1 ""
	assert_output proceed
}

# --- mode=dirty, no --watch, dirty: prefer live, else one-shot overlay ------

@test "decide: dirty, mutagen present -> watch (default to live)" {
	run cs_sync_decide_uncommitted 1 "" dirty "" "" "" 1
	assert_output watch
}

@test "decide: dirty, no mutagen -> overlay" {
	run cs_sync_decide_uncommitted 1 "" dirty "" "" "" ""
	assert_output overlay
}

@test "decide: dirty, --once forces overlay even with mutagen" {
	run cs_sync_decide_uncommitted 1 "" dirty "" 1 "" 1
	assert_output overlay
}

# --- overlay safety gate: never clobber the remote's uncommitted work -------

@test "decide: overlay blocked when remote dirty (non-interactive) -> abort" {
	run cs_sync_decide_uncommitted 1 1 dirty "" 1 "" ""
	assert_output abort
}

@test "decide: overlay blocked when remote dirty (interactive) -> prompt" {
	run cs_sync_decide_uncommitted 1 1 dirty "" 1 1 ""
	assert_output prompt
}

@test "decide: only remote dirty, no mutagen, interactive -> prompt (overlay would clobber)" {
	run cs_sync_decide_uncommitted "" 1 dirty "" "" 1 ""
	assert_output prompt
}

@test "decide: both dirty, mutagen present -> watch (live reconciles, no overlay gate)" {
	run cs_sync_decide_uncommitted 1 1 dirty "" "" 1 1
	assert_output watch
}
