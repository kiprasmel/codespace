#!/usr/bin/env bats

# CODESPACE_CONFIG_ROOT central default (codespace-utils): when the env var is
# unset AND the conventional ~/codespace-config dir exists, sourcing the shared
# init resolves it automatically so sync/dev/create work without the env var. An
# explicit value always wins; absent dir + unset var stays unset (callers that
# truly need it still error clearly).

load helpers

setup() { common_setup; }

# source codespace-utils in a clean subshell (HOME is the per-test sandbox) and
# print the resolved CODESPACE_CONFIG_ROOT.
resolve_ccr() {
	bash -c 'source "'"$REPO_ROOT"'/codespace-utils"; printf "%s" "${CODESPACE_CONFIG_ROOT:-<unset>}"'
}

@test "config-root default: unset + ~/codespace-config exists -> defaults to it" {
	mkdir -p "$HOME/codespace-config"
	unset CODESPACE_CONFIG_ROOT
	run resolve_ccr
	assert_output "$HOME/codespace-config"
}

@test "config-root default: unset + no ~/codespace-config -> stays unset" {
	# common_setup already unset it and the sandbox HOME has no codespace-config
	unset CODESPACE_CONFIG_ROOT
	run resolve_ccr
	assert_output "<unset>"
}

@test "config-root default: an explicit value always wins over the default dir" {
	mkdir -p "$HOME/codespace-config"
	export CODESPACE_CONFIG_ROOT="$BATS_TEST_TMPDIR/explicit"
	mkdir -p "$CODESPACE_CONFIG_ROOT"
	run resolve_ccr
	assert_output "$BATS_TEST_TMPDIR/explicit"
}
