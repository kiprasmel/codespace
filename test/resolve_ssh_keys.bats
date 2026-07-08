#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	source_utils

	REPO="$SANDBOX/org/myrepo"
	mkrepo "$REPO"
}

# --- cs_ssh_target_from_url ---------------------------------------------------

@test "ssh_target_from_url: scp-style git@host:org/repo.git" {
	run cs_ssh_target_from_url "git@github.com:sintra-ai/core.git"
	assert_success
	assert_output "git@github.com"
}

@test "ssh_target_from_url: ssh:// url keeps user, drops path" {
	run cs_ssh_target_from_url "ssh://git@github.com/org/repo"
	assert_success
	assert_output "git@github.com"
}

@test "ssh_target_from_url: https url drops user + path" {
	run cs_ssh_target_from_url "https://user@gitlab.com/org/repo.git"
	assert_success
	assert_output "gitlab.com"
}

@test "ssh_target_from_url: userless scp form" {
	run cs_ssh_target_from_url "github.com:org/repo"
	assert_success
	assert_output "github.com"
}

@test "ssh_target_from_url: unparseable -> non-zero" {
	run cs_ssh_target_from_url "not-a-url"
	assert_failure
}

# --- cs_find_repo_org_config --------------------------------------------------

@test "find_repo_org_config: per-repo wins over per-org, .codespace/ over root" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace" "$CODESPACE_CONFIG_ROOT/org/.codespace"
	echo repo > "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace/ssh-key"
	echo root > "$CODESPACE_CONFIG_ROOT/org/myrepo/ssh-key"
	echo org  > "$CODESPACE_CONFIG_ROOT/org/.codespace/ssh-key"

	cd "$REPO"
	run cs_find_repo_org_config ssh-key
	assert_success
	assert_output "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace/ssh-key"
}

@test "find_repo_org_config: explicit repo_id, per-org fallback" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/.codespace"
	echo org > "$CODESPACE_CONFIG_ROOT/org/.codespace/ssh-key"

	run cs_find_repo_org_config ssh-key "org/other"
	assert_success
	assert_output "$CODESPACE_CONFIG_ROOT/org/.codespace/ssh-key"
}

@test "find_repo_org_config: nothing found -> non-zero" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	run cs_find_repo_org_config ssh-key "org/other"
	assert_failure
}

# --- cs_resolve_ssh_keys ------------------------------------------------------

@test "resolve_ssh_keys: CS_SSH_KEY comma list -- trimmed, ~ expanded, # dropped" {
	export CS_SSH_KEY="~/.ssh/a , /tmp/b ,# a comment, ~/.ssh/c"
	run cs_resolve_ssh_keys
	assert_success
	assert_line --index 0 "$HOME/.ssh/a"
	assert_line --index 1 "/tmp/b"
	assert_line --index 2 "$HOME/.ssh/c"
	assert_equal "${#lines[@]}" 3
}

@test "resolve_ssh_keys: CS_SSH_KEY overrides the config file" {
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace"
	echo /tmp/fromfile > "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace/ssh-key"
	export CS_SSH_KEY="/tmp/fromenv"

	cd "$REPO"
	run cs_resolve_ssh_keys
	assert_success
	assert_output "/tmp/fromenv"
}

@test "resolve_ssh_keys: file with newlines + commas + comments + blanks" {
	unset CS_SSH_KEY
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace"
	printf '# keys\n~/.ssh/k1\n/tmp/k2, /tmp/k3\n\n' \
		> "$CODESPACE_CONFIG_ROOT/org/myrepo/.codespace/ssh-key"

	cd "$REPO"
	run cs_resolve_ssh_keys
	assert_success
	assert_line --index 0 "$HOME/.ssh/k1"
	assert_line --index 1 "/tmp/k2"
	assert_line --index 2 "/tmp/k3"
	assert_equal "${#lines[@]}" 3
}

@test "resolve_ssh_keys: per-org file used when no per-repo file" {
	unset CS_SSH_KEY
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	mkdir -p "$CODESPACE_CONFIG_ROOT/org/.codespace"
	echo /tmp/org_key > "$CODESPACE_CONFIG_ROOT/org/.codespace/ssh-key"

	cd "$REPO"
	run cs_resolve_ssh_keys
	assert_success
	assert_output "/tmp/org_key"
}

@test "resolve_ssh_keys: nothing configured -> empty, success" {
	unset CS_SSH_KEY
	export CODESPACE_CONFIG_ROOT="$SANDBOX/config"
	cd "$REPO"
	run cs_resolve_ssh_keys
	assert_success
	assert_output ""
}
