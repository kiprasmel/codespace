#!/usr/bin/env bats

# Pure decision over (dirty flags, user flags) -> action token.
# Args: local_dirty remote_dirty want once interactive mutagen_ok sticky_live

load helpers

setup() {
	common_setup
	source_sync
}

@test "decide: both clean -> proceed" {
	run cs_sync_decide_uncommitted "" "" "" "" 1 "" ""
	assert_output proceed
}

@test "decide: --watch always wins, even when clean" {
	run cs_sync_decide_uncommitted "" "" watch "" 1 1 ""
	assert_output watch
}

@test "decide: --watch wins even when both dirty" {
	run cs_sync_decide_uncommitted 1 1 watch "" 1 1 ""
	assert_output watch
}

@test "decide: local dirty, no flag, interactive -> prompt" {
	run cs_sync_decide_uncommitted 1 "" "" "" 1 "" ""
	assert_output prompt
}

@test "decide: local dirty, no flag, non-interactive -> abort" {
	run cs_sync_decide_uncommitted 1 "" "" "" "" "" ""
	assert_output abort
}

@test "decide: --commit -> commit" {
	run cs_sync_decide_uncommitted 1 "" commit "" "" "" ""
	assert_output commit
}

@test "decide: --uncommitted --once -> overlay" {
	run cs_sync_decide_uncommitted 1 "" uncommitted 1 "" "" ""
	assert_output overlay
}

@test "decide: --uncommitted with mutagen -> watch" {
	run cs_sync_decide_uncommitted 1 "" uncommitted "" "" 1 ""
	assert_output watch
}

@test "decide: --uncommitted without mutagen -> overlay" {
	run cs_sync_decide_uncommitted 1 "" uncommitted "" "" "" ""
	assert_output overlay
}

@test "decide: overlay blocked when remote dirty (non-interactive) -> abort" {
	run cs_sync_decide_uncommitted 1 1 uncommitted 1 "" "" ""
	assert_output abort
}

@test "decide: overlay blocked when remote dirty (interactive) -> prompt" {
	run cs_sync_decide_uncommitted 1 1 uncommitted 1 1 "" ""
	assert_output prompt
}

@test "decide: sticky live + mutagen + dirty -> watch" {
	run cs_sync_decide_uncommitted 1 "" "" "" 1 1 1
	assert_output watch
}

@test "decide: sticky live without mutagen falls back to prompt (interactive)" {
	run cs_sync_decide_uncommitted 1 "" "" "" 1 "" 1
	assert_output prompt
}
