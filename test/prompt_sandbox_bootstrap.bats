#!/usr/bin/env bats

# `codespace prompt sandbox-bootstrap` — the agent-prompt generator. Verifies the
# dispatch surface, that the detector reports each repo's OWN documented setup
# signals (README / Makefile / .python-version / package.json), that the contract
# is embedded, and that no template placeholders leak through.

load helpers

setup() {
	common_setup
	export CODESPACE_CONFIG_ROOT="$BATS_TEST_TMPDIR/cfg"
	mkdir -p "$CODESPACE_CONFIG_ROOT"
}

# a fixture repo carrying the real dev-setup signals the detector keys off.
mk_fixture_repo() {
	local d="$1"
	mkdir -p "$d"
	printf '# myrepo\n\n## Setup\n\nrun make setup.\n' > "$d/README.md"
	printf 'setup: setup-system install\ninstall:\n\tpoetry install\napi:\n\techo run\n' > "$d/Makefile"
	printf '3.11\n' > "$d/.python-version"
	printf '{"name":"x","packageManager":"pnpm@10.32.1","engines":{"node":">=22"},"scripts":{"dev":"x"}}\n' > "$d/package.json"
}

@test "dispatch: 'codespace prompt -h' prints usage and exits 0" {
	run "$REPO_ROOT/codespace" prompt -h
	assert_success
	assert_output --partial "codespace prompt"
	assert_output --partial "sandbox-bootstrap"
}

@test "dispatch: unknown prompt topic errors" {
	run "$REPO_ROOT/codespace" prompt bogus-topic
	assert_failure
	assert_output --partial "unknown prompt topic"
}

@test "sandbox-bootstrap: renders detected per-repo facts + embeds the contract" {
	mk_fixture_repo "$BATS_TEST_TMPDIR/myrepo"
	run "$REPO_ROOT/codespace" prompt sandbox-bootstrap "$BATS_TEST_TMPDIR/myrepo"
	assert_success
	# detector picked up each signal
	assert_output --partial "### myrepo"
	assert_output --partial "README: \`README.md\`"
	assert_output --partial "Makefile targets:"
	assert_output --partial ".python-version: \`3.11\`"
	assert_output --partial "packageManager=\`pnpm@10.32.1\`"
	assert_output --partial "engines.node=\`>=22\`"
	# the contract is embedded (the section header + a contract-only heading)
	assert_output --partial "# CONTRACT"
	assert_output --partial "## The three hooks"
}

@test "sandbox-bootstrap: leaves no unfilled {{placeholders}}" {
	mk_fixture_repo "$BATS_TEST_TMPDIR/myrepo"
	run "$REPO_ROOT/codespace" prompt sandbox-bootstrap "$BATS_TEST_TMPDIR/myrepo"
	assert_success
	refute_output --partial '{{'
	refute_output --partial '}}'
}
