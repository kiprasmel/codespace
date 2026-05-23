#!/usr/bin/env bats

# cs_collect_remote_files — runs the local post-create script in a mktemp
# sandbox with CS_REMOTE_FILE_COLLECT=1 to discover which files
# link-files-from-{repo,config} would link, without actually linking.
#
# Sandbox is wiped at the end; manifest path is printed to stdout (caller rm's).

load helpers

setup() {
	common_setup
	source_utils

	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"

	# resolution uses the LOCAL base repo (cs_abs_path_base_repo); cd into
	# it so the resolver finds the repo-committed .codespace/post-create.
	cd "$REPO"

	# the bats $PATH already has REPO_ROOT (so `codespace post-create.link-files-*`
	# subcommands resolve to our working-tree script).
}

# helper: write a post-create script at $REPO/.codespace/post-create
mk_pc() {
	mkdir -p "$REPO/.codespace"
	cat > "$REPO/.codespace/post-create" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$1
EOF
	chmod +x "$REPO/.codespace/post-create"
}

@test "collect: no post-create -> empty manifest, success" {
	run cs_collect_remote_files
	assert_success
	# stdout is the manifest path
	manifest="$output"
	[ -f "$manifest" ]
	[ ! -s "$manifest" ]
	rm -f "$manifest"
}

@test "collect: static link calls -> manifest has repo:/config: lines" {
	mk_pc '
codespace post-create.link-files-from-repo .env
codespace post-create.link-files-from-config AGENTS.md
'

	run cs_collect_remote_files
	assert_success
	manifest="$output"

	[ -f "$manifest" ]
	grep -qx 'repo:.env' "$manifest"
	grep -qx 'config:AGENTS.md' "$manifest"

	rm -f "$manifest"
}

@test "collect: variable expansion -> records expanded values" {
	mk_pc '
REPO_FILES=".env .env.local"
codespace post-create.link-files-from-repo $REPO_FILES
'

	run cs_collect_remote_files
	assert_success
	manifest="$output"
	grep -qx 'repo:.env' "$manifest"
	grep -qx 'repo:.env.local' "$manifest"
	rm -f "$manifest"
}

@test "collect: non-link command does not corrupt the manifest" {
	# touch a file in the sandbox cwd before linking — runs for real, harmless
	mk_pc '
touch some-side-effect-file
codespace post-create.link-files-from-repo .env
'

	run cs_collect_remote_files
	assert_success
	manifest="$output"
	grep -qx 'repo:.env' "$manifest"
	# the side-effect file should NOT be in the user's working dir:
	[ ! -e "$PWD/some-side-effect-file" ]
	rm -f "$manifest"
}

@test "collect: failing setup command after links -> partial manifest captured" {
	mk_pc '
codespace post-create.link-files-from-repo .env
false
codespace post-create.link-files-from-repo .env.too-late
'

	run cs_collect_remote_files
	assert_success
	manifest="$output"
	grep -qx 'repo:.env' "$manifest"
	# the line after `false` must NOT have been recorded
	! grep -qx 'repo:.env.too-late' "$manifest"
	rm -f "$manifest"
}

@test "collect: resolves via \$CODESPACE_CONFIG_ROOT, not the cwd" {
	# regression: the create flow used to pass the (non-existent) stub path
	# to the resolver, which silently produced an empty manifest. now we
	# resolve from cs_abs_path_base_repo (the LOCAL repo we're invoked from)
	# even if the user's repo has no committed .codespace/, as long as the
	# user's layer2 config does.
	#
	# layer2 setup: $CODESPACE_CONFIG_ROOT/<repo-id>/.codespace/post-create
	# (no repo-committed .codespace/)
	export CODESPACE_CONFIG_ROOT="$SANDBOX/layer2"
	repo_id="org/myrepo"
	mkdir -p "$CODESPACE_CONFIG_ROOT/$repo_id/.codespace"
	cat > "$CODESPACE_CONFIG_ROOT/$repo_id/.codespace/post-create" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
codespace post-create.link-files-from-config AGENTS.md
EOF
	chmod +x "$CODESPACE_CONFIG_ROOT/$repo_id/.codespace/post-create"

	# repo has NO .codespace/ — user-level layer2 is the only source.
	[ ! -d "$REPO/.codespace" ]

	manifest="$(cs_collect_remote_files)"
	[ -s "$manifest" ] || { echo "expected non-empty manifest" >&2; cat "$manifest" >&2; false; }
	grep -qx 'config:AGENTS.md' "$manifest"
	rm -f "$manifest"
}

@test "collect: outside any git repo -> empty manifest, success" {
	# regression: -r --clone may run from a non-git cwd. cs_abs_path_base_repo
	# fails -> we silently produce an empty manifest, no crash.
	cd "$SANDBOX"  # not a git repo
	manifest="$(cs_collect_remote_files)"
	[ -f "$manifest" ]
	[ ! -s "$manifest" ]
	rm -f "$manifest"
}

@test "collect: sandbox is wiped after collect returns" {
	# script touches a file in cwd; we observe that the parent dir of that
	# file is gone after collect returns (i.e. the sandbox was wiped).
	mk_pc '
touch sandbox-marker
codespace post-create.link-files-from-repo .env
'

	# capture the sandbox path indirectly: the marker file lives in the
	# sandbox dir, so by listing /tmp/cs-collect.* before vs after, we can
	# verify nothing was left behind.
	pre="$(ls -d /tmp/cs-collect.* /var/folders/*/T/cs-collect.* 2>/dev/null | wc -l | tr -d ' ')"

	manifest="$(cs_collect_remote_files)"

	post="$(ls -d /tmp/cs-collect.* /var/folders/*/T/cs-collect.* 2>/dev/null | wc -l | tr -d ' ')"
	[ "$pre" = "$post" ]

	# manifest still captured the link declaration
	grep -qx 'repo:.env' "$manifest"
	rm -f "$manifest"
}
