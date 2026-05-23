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
