#!/usr/bin/env bats

# End-to-end stack per-repo init flow with shimmed ssh/rsync. Mirrors
# remote_create_e2e.bats but exercises cs_stack_init_repo_remote with the
# globals the stack flow sets up. Catches the parity gaps with single-repo -r:
# collect+ship per repo, PATH + CS_REMOTE_CODESPACE wiring, and (in commit 5)
# marker schema.

load helpers

setup() {
	common_setup
	source_utils
	source_stack
	# shellcheck disable=SC1090
	source "$REPO_ROOT/codespace-remote"

	export SHIM_LOG_STDIN=1
	install_ssh_shims
	export CS_NO_EDIT=1

	# real local base repo at $HOME/sintra/core (so cs_remote_relpath_for_local
	# derives 'sintra/core' relative to $HOME)
	REPO="$SANDBOX/sintra/core"
	mkrepo "$REPO"
	echo "secret" > "$REPO/.env"

	# real layer2 config dir for this repo (per-repo post-create that declares
	# a repo file (.env) and a config file (AGENTS.md))
	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	mkdir -p "$CODESPACE_CONFIG_ROOT/sintra/core/.codespace"
	echo "agents" > "$CODESPACE_CONFIG_ROOT/sintra/core/AGENTS.md"
	cat > "$CODESPACE_CONFIG_ROOT/sintra/core/.codespace/post-create" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
codespace post-create.link-files-from-repo .env
codespace post-create.link-files-from-config AGENTS.md
EOF
	chmod +x "$CODESPACE_CONFIG_ROOT/sintra/core/.codespace/post-create"

	# globals consumed by cs_stack_init_repo_remote
	export r_name="core"
	export r_clone_url="git@github.com:sintra-ai/core.git"
	# r_dest is the local stub path (we'll cd elsewhere to mimic the real
	# spawn flow where cwd is the user's invocation dir, NOT r_base)
	export r_dest="$SANDBOX/sintra/stack_si-feat/core"
	export r_base="$REPO"
	export branch_name="si-feat"
	export r_base_branch=""
	export remote_host="user@host"
	export create_mode="worktree"

	# spawn parent's cwd is the user's invocation dir, not r_base. Pick
	# something that's not a git repo to ensure ship/collect rely on the
	# explicitly-passed r_base (regression for the cwd-resolution issue).
	cd "$SANDBOX"
}

@test "stack init-repo remote e2e: ships per-repo declared files (parity with single-repo -r)" {
	run --separate-stderr cs_stack_init_repo_remote </dev/null
	assert_success

	# the create flow announced shipping each declared file (regression for
	# stack flow not running collect+ship at all)
	[[ "$stderr" == *"==> [user@host] shipping config:AGENTS.md"* ]]
	[[ "$stderr" == *"==> [user@host] shipping repo:.env"* ]]

	# rsync invocations went out for both files, against the per-repo r_base
	log="$(cat "$SHIM_LOG")"
	[[ "$log" == *"$REPO/.env"*"user@host:codespace/sintra/stack_si-feat/core/.env"* ]]
	[[ "$log" == *"$CODESPACE_CONFIG_ROOT/sintra/core/AGENTS.md"*"user@host:codespace/sintra/stack_si-feat/core/AGENTS.md"* ]]
}

@test "stack init-repo remote e2e: bootstrap + post-create heredocs include PATH and CS_REMOTE_CODESPACE" {
	cs_stack_init_repo_remote </dev/null

	log="$(cat "$SHIM_LOG")"
	# regression: non-interactive ssh sessions need explicit PATH for codespace
	# child invocations to find ~/.local/bin/codespace.
	[[ "$log" == *'export PATH="$HOME/.local/bin:$PATH"'* ]]
	# regression: skip+verify mode wired in for stack remote post-create too.
	[[ "$log" == *"export CS_REMOTE_CODESPACE=1"* ]]
	[[ "$log" == *'codespace post-create "$dest_abs"'* ]]
}

@test "stack init-repo remote e2e: per-repo stub marker uses relpath= schema" {
	cs_stack_init_repo_remote </dev/null

	[ -f "$r_dest/.codespace-remote" ]
	# new schema: relpath=<rel> (no $HOME/ prefix). Single-repo flow already
	# writes this; stack flow now matches.
	grep -q '^relpath=codespace/sintra/stack_si-feat/core$' "$r_dest/.codespace-remote"
	grep -q '^host=user@host$' "$r_dest/.codespace-remote"
	grep -q '^kind=worktree$' "$r_dest/.codespace-remote"
	# fully-provisioned repo records a clean setup status
	grep -q '^setup_status=ok$' "$r_dest/.codespace-remote"
	# legacy 'path=$HOME/...' must NOT be written
	! grep -q '^path=' "$r_dest/.codespace-remote"
}

# --- marker robustness: a provisioned worktree must be findable even when the
# app-level post-create (e.g. a toolchain-less `make setup`) fails. -----------

@test "stack init-repo remote e2e: post-create failure still stamps the marker (setup_status=failed) + returns 2" {
	# clone/worktree provisioning + ship succeed (shimmed ssh); only the
	# app-level post-create fails.
	cs_remote_run_post_create() { return 1; }

	run cs_stack_init_repo_remote </dev/null
	# rc 2 = "provisioned, setup failed" (non-zero, so the summary still flags it)
	[ "$status" -eq 2 ]

	# the worktree WAS provisioned, so the stub marker must exist (open/rm can
	# resolve it) and record the failure.
	[ -f "$r_dest/.codespace-remote" ]
	grep -q '^relpath=codespace/sintra/stack_si-feat/core$' "$r_dest/.codespace-remote"
	grep -q '^setup_status=failed$' "$r_dest/.codespace-remote"
}

@test "stack init-repo remote e2e: bootstrap failure is also non-fatal to the marker (setup_status=failed, rc 2)" {
	cs_remote_run_bootstrap() { return 1; }
	# post-create must be SKIPPED once bootstrap fails
	POSTCREATE_RAN="$BATS_TEST_TMPDIR/pc.ran"
	cs_remote_run_post_create() { touch "$POSTCREATE_RAN"; }

	run cs_stack_init_repo_remote </dev/null
	[ "$status" -eq 2 ]
	assert [ ! -f "$POSTCREATE_RAN" ]
	[ -f "$r_dest/.codespace-remote" ]
	grep -q '^setup_status=failed$' "$r_dest/.codespace-remote"
}

@test "stack init-repo remote e2e: provisioning (clone/worktree) failure writes NO marker + returns 1" {
	# the create step itself fails -> nothing was provisioned.
	cs_remote_init_create() { return 1; }
	rm -rf "$r_dest"

	run cs_stack_init_repo_remote </dev/null
	[ "$status" -eq 1 ]
	# no provisioned worktree -> no stub marker to mislead open/rm
	[ ! -f "$r_dest/.codespace-remote" ]
}
