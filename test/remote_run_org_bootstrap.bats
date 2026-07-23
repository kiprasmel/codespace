#!/usr/bin/env bats

# Verify the ORG/STACK-COMMON bootstrap level (sibling of the per-repo hook):
# - cs_remote_run_org_bootstrap resolves from the shipped stack-config dir and
#   passes the CS_STACK_* env block over ssh (once).
# - failure propagates.
# - run-order: cs_stack_create runs the org bootstrap BEFORE spawning the
#   parallel per-repo jobs.

load helpers

setup() {
	common_setup
	source_utils
	install_ssh_shims
	export SHIM_LOG_STDIN=1
}

@test "run_org_bootstrap: invokes ssh exactly once with the script body on stdin" {
	run cs_remote_run_org_bootstrap "cs-sandbox-feat" "sintra" "core,superepo,mobile" "default" "feat"
	assert_success

	run grep -c '^ssh ' "$SHIM_LOG"
	assert_output "1"
}

@test "run_org_bootstrap: resolves the org hook under codespace-config/<config_rel> and exports CS_STACK_*" {
	run cs_remote_run_org_bootstrap "cs-sandbox-feat" "sintra" "core,superepo,mobile" "default" "feat"
	assert_success

	log="$(cat "$SHIM_LOG")"
	# positional args carried to the remote heredoc
	[[ "$log" == *"cs-sandbox-feat"* ]]
	[[ "$log" == *"sintra"* ]]
	# %q shim-quoting escapes the commas in the csv (core\,superepo\,mobile),
	# so match the individual repo names rather than the raw csv.
	[[ "$log" == *"core"* ]]
	[[ "$log" == *"superepo"* ]]
	[[ "$log" == *"mobile"* ]]
	[[ "$log" == *"default"* ]]

	# the remote body resolves the org-common hook under the shipped config dir
	[[ "$log" == *'codespace-config/'* ]]
	[[ "$log" == *"remote-bootstrap.sh"* ]]

	# stack-common env block is exported (distinct from per-repo CS_REPO_ID/etc)
	[[ "$log" == *"export CS_STACK_NAME="* ]]
	[[ "$log" == *"export CS_STACK_BRANCH="* ]]
	[[ "$log" == *"export CS_STACK_REPOS="* ]]
	[[ "$log" == *"export CS_STACK_CONFIG_DIR="* ]]
	[[ "$log" == *"export CS_REMOTE_CODESPACE="* ]]
}

@test "run_org_bootstrap: failure exit propagates" {
	export SSH_NEXT_RC=42
	run cs_remote_run_org_bootstrap "cs-sandbox-feat" "sintra" "core" "default" "feat"
	assert_failure
	[ "$status" -eq 42 ]
}

@test "run_org_bootstrap: run-order — cs_stack_create runs org bootstrap before per-repo spawn" {
	source_stack
	# Inspect the parsed function body (robust to reformatting) and assert the
	# org-common bootstrap call precedes the parallel per-repo job spawn.
	body="$(declare -f cs_stack_create)"
	org_line="$(printf '%s\n' "$body" | grep -n 'cs_stack_run_org_bootstrap' | head -n1 | cut -d: -f1)"
	spawn_line="$(printf '%s\n' "$body" | grep -n 'cs_stack_create_spawn_jobs' | head -n1 | cut -d: -f1)"
	[ -n "$org_line" ] || { echo "cs_stack_run_org_bootstrap not called in cs_stack_create"; false; }
	[ -n "$spawn_line" ] || { echo "cs_stack_create_spawn_jobs not called in cs_stack_create"; false; }
	[ "$org_line" -lt "$spawn_line" ] || { echo "org bootstrap ($org_line) must precede spawn ($spawn_line)"; false; }
}
