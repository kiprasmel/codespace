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
	run cs_collect_remote_files "$REPO"
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

	run cs_collect_remote_files "$REPO"
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

	run cs_collect_remote_files "$REPO"
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

	run cs_collect_remote_files "$REPO"
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

	run cs_collect_remote_files "$REPO"
	assert_success
	manifest="$output"
	grep -qx 'repo:.env' "$manifest"
	# the line after `false` must NOT have been recorded
	! grep -qx 'repo:.env.too-late' "$manifest"
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

	manifest="$(cs_collect_remote_files "$REPO")"

	post="$(ls -d /tmp/cs-collect.* /var/folders/*/T/cs-collect.* 2>/dev/null | wc -l | tr -d ' ')"
	[ "$pre" = "$post" ]

	# manifest still captured the link declaration
	grep -qx 'repo:.env' "$manifest"
	rm -f "$manifest"
}
