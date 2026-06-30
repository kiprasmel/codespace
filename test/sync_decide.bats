#!/usr/bin/env bats

# Pure decision over (dirty flags, mode, live, interactive) -> action token.
# Args: local_dirty remote_dirty sync_mode live interactive
# Tokens: proceed | overlay | watch | prompt | abort
#
# No stickiness: a plain sync (no --watch) never auto-engages a live session --
# it's a one-shot. Only --watch (live) returns `watch`.

load helpers

setup() {
	common_setup
	source_sync
}

# --- mode=commits: never touch the working tree -----------------------------

@test "decide: mode=commits, clean -> proceed" {
	run cs_sync_decide_uncommitted "" "" commits "" 1
	assert_output proceed
}

@test "decide: mode=commits leaves local dirty alone -> proceed" {
	run cs_sync_decide_uncommitted 1 "" commits "" 1
	assert_output proceed
}

@test "decide: mode=commits with both sides dirty -> proceed" {
	run cs_sync_decide_uncommitted 1 1 commits "" 1
	assert_output proceed
}

# --- --watch (live) always engages, even on a clean tree --------------------

@test "decide: live on a clean tree -> watch (engage + wait for changes)" {
	run cs_sync_decide_uncommitted "" "" dirty 1 1
	assert_output watch
}

@test "decide: live always -> watch (clean, non-interactive)" {
	run cs_sync_decide_uncommitted "" "" dirty 1 ""
	assert_output watch
}

@test "decide: live on a dirty tree -> watch" {
	run cs_sync_decide_uncommitted 1 "" dirty 1 1
	assert_output watch
}

@test "decide: live wins when both dirty" {
	run cs_sync_decide_uncommitted 1 1 dirty 1 1
	assert_output watch
}

# --- mode=dirty, no --watch: clean short-circuits, dirty overlays once ------

@test "decide: mode=dirty, both clean, no watch -> proceed" {
	run cs_sync_decide_uncommitted "" "" dirty "" 1
	assert_output proceed
}

@test "decide: dirty, no watch -> one-shot overlay (no stickiness)" {
	run cs_sync_decide_uncommitted 1 "" dirty "" ""
	assert_output overlay
}

@test "decide: dirty, no watch, interactive -> overlay (still one-shot)" {
	run cs_sync_decide_uncommitted 1 "" dirty "" 1
	assert_output overlay
}

# --- overlay safety gate: never clobber the remote's uncommitted work -------

@test "decide: overlay blocked when remote dirty (non-interactive) -> abort" {
	run cs_sync_decide_uncommitted 1 1 dirty "" ""
	assert_output abort
}

@test "decide: overlay blocked when remote dirty (interactive) -> prompt" {
	run cs_sync_decide_uncommitted 1 1 dirty "" 1
	assert_output prompt
}

@test "decide: only remote dirty, interactive -> prompt (overlay would clobber)" {
	run cs_sync_decide_uncommitted "" 1 dirty "" 1
	assert_output prompt
}

@test "decide: only remote dirty, non-interactive -> abort" {
	run cs_sync_decide_uncommitted "" 1 dirty "" ""
	assert_output abort
}
