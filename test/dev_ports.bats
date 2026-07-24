#!/usr/bin/env bats

# `codespace dev` CLIENT — the pure, host-hermetic pieces:
#   - url slug sanitization (branch -> DNS-safe subdomain)
#   - port resolution precedence helpers (manifest / stacks.json dev map / hints)
#   - port-plan construction (plain 1:1 vs. ephemeral+slug urls)
#   - Caddyfile regeneration from the session registry (multi-stack routing)
#   - session file round-trip
# The remote/tunnel/proxy-process bits are exercised by the run-order + dispatch
# checks; live forwarding is validated on white-monster (Phase B).

load helpers

setup() {
	common_setup
	# cs_dev_cache_dir prefers $CODESPACE_CONFIG_ROOT/.cache (via cs_cache_dir);
	# pin it into the per-test sandbox so caddy/session files stay hermetic.
	export CODESPACE_CONFIG_ROOT="$BATS_TEST_TMPDIR/cfg"
	mkdir -p "$CODESPACE_CONFIG_ROOT"
	source_dev
}

# --- url slug ---------------------------------------------------------------

@test "url_slug: lowercases, replaces non-alnum, collapses + trims dashes" {
	run cs_dev_url_slug "Feature/Foo_Bar"
	assert_output "feature-foo-bar"
}

@test "url_slug: strips leading/trailing separators and repeats" {
	run cs_dev_url_slug "--Weird__Name--"
	assert_output "weird-name"
}

# --- manifest parsing -------------------------------------------------------

@test "parse_manifest: emits label/port/scheme with web=>https default" {
	run bash -c 'source '"$REPO_ROOT"'/codespace-utils; CS_DEV_NO_RUN=1 source '"$REPO_ROOT"'/codespace-dev; printf "%s" "{\"ports\":[{\"port\":3000,\"label\":\"web\"},{\"port\":8000,\"label\":\"core-api\"}]}" | cs_dev_parse_manifest'
	assert_line --index 0 "$(printf 'web\t3000\thttps')"
	assert_line --index 1 "$(printf 'core-api\t8000\thttp')"
}

@test "parse_manifest: explicit scheme in the manifest is preserved" {
	run bash -c 'source '"$REPO_ROOT"'/codespace-utils; CS_DEV_NO_RUN=1 source '"$REPO_ROOT"'/codespace-dev; printf "%s" "{\"ports\":[{\"port\":8443,\"label\":\"api\",\"scheme\":\"https\"}]}" | cs_dev_parse_manifest'
	assert_output "$(printf 'api\t8443\thttps')"
}

# --- stacks.json dev map ----------------------------------------------------

@test "ports_from_stacks_json: reads a top-level .dev map" {
	sj="$BATS_TEST_TMPDIR/stacks.json"
	printf '%s' '{"version":"0","dev":{"web":3000,"core-api":8000},"stacks":{}}' > "$sj"
	run cs_dev_ports_from_stacks_json "$sj" default
	assert_line --index 0 "$(printf 'web\t3000\thttps')"
	assert_line --index 1 "$(printf 'core-api\t8000\thttp')"
}

@test "ports_from_stacks_json: reads a per-stack .dev object" {
	sj="$BATS_TEST_TMPDIR/stacks.json"
	printf '%s' '{"version":"0","stacks":{"sintra":{"dev":{"web":3001}}}}' > "$sj"
	run cs_dev_ports_from_stacks_json "$sj" sintra
	assert_output "$(printf 'web\t3001\thttps')"
}

@test "ports_from_stacks_json: missing file is a silent no-op" {
	run cs_dev_ports_from_stacks_json "$BATS_TEST_TMPDIR/nope.json" default
	assert_success
	assert_output ""
}

@test "ports_from_stacks_json: structured 'dev' with .ports (timeout ignored as a port)" {
	sj="$BATS_TEST_TMPDIR/stacks.json"
	printf '%s' '{"version":"0","dev":{"timeout":420,"ports":{"web":3000,"core-api":8000}}}' > "$sj"
	run cs_dev_ports_from_stacks_json "$sj" default
	assert_line --index 0 "$(printf 'web\t3000\thttps')"
	assert_line --index 1 "$(printf 'core-api\t8000\thttp')"
	# the reserved 'timeout' key must NOT surface as a port row
	refute_output --partial "timeout"
}

# --- timeout config ---------------------------------------------------------

@test "timeout_from_stacks_json: reads reserved dev.timeout (structured form)" {
	sj="$BATS_TEST_TMPDIR/stacks.json"
	printf '%s' '{"version":"0","dev":{"timeout":420,"ports":{"web":3000}}}' > "$sj"
	run cs_dev_timeout_from_stacks_json "$sj" default
	assert_output "420"
}

@test "timeout_from_stacks_json: flat dev map (no timeout) is empty" {
	sj="$BATS_TEST_TMPDIR/stacks.json"
	printf '%s' '{"version":"0","dev":{"web":3000,"core-api":8000}}' > "$sj"
	run cs_dev_timeout_from_stacks_json "$sj" default
	assert_output ""
}

# --- static # CS_DEV: hints -------------------------------------------------

@test "ports_from_hints: parses '# CS_DEV:' label=port[:scheme] tokens" {
	f="$BATS_TEST_TMPDIR/dev.sh"
	printf '#!/usr/bin/env bash\n# CS_DEV: web=3000:https core-api=8000 backend=8002\n' > "$f"
	run cs_dev_ports_from_hints "$f"
	assert_line --index 0 "$(printf 'web\t3000\thttps')"
	assert_line --index 1 "$(printf 'core-api\t8000\thttp')"
	assert_line --index 2 "$(printf 'backend\t8002\thttp')"
}

# --- port union (manifest + static, manifest wins) --------------------------

@test "merge_ports: runtime manifest wins per-label; static fills missing labels" {
	# manifest (runtime) has web+backend with a runtime port for web; static
	# (stacks.json dev map) additionally declares core-api and a different web port.
	manifest="$(printf 'web\t3100\thttps\nbackend\t8002\thttp')"
	static="$(printf 'web\t3000\thttps\ncore-api\t8000\thttp\nbackend\t8002\thttp')"
	run cs_dev_merge_ports "$manifest" "$static"
	# web resolves to the manifest's runtime port (3100), not the static 3000
	assert_line --index 0 "$(printf 'web\t3100\thttps')"
	assert_line --index 1 "$(printf 'backend\t8002\thttp')"
	# core-api, absent from the manifest, is filled from the static map
	assert_line --index 2 "$(printf 'core-api\t8000\thttp')"
	# exactly three unique labels (no duplicate web/backend rows)
	assert_equal "${#lines[@]}" 3
}

@test "merge_ports: an empty manifest falls back entirely to the static map" {
	static="$(printf 'web\t3000\thttps\ncore-api\t8000\thttp')"
	run cs_dev_merge_ports "" "$static"
	assert_line --index 0 "$(printf 'web\t3000\thttps')"
	assert_line --index 1 "$(printf 'core-api\t8000\thttp')"
	assert_equal "${#lines[@]}" 2
}

@test "merge_ports: blank/malformed rows are dropped" {
	# a header-ish blank line + a label with no port must not produce rows
	run cs_dev_merge_ports "$(printf '\nweb\t3000\thttps\nbroken\t\thttp')" ""
	assert_output "$(printf 'web\t3000\thttps')"
}

# --- port plan --------------------------------------------------------------

@test "build_port_plan: --plain maps local=remote and uses raw 127.0.0.1 urls" {
	plan="$(printf 'web\t3000\thttps\ncore-api\t8000\thttp\n' | cs_dev_build_port_plan "feature-x" 1)"
	run jq -r '.[0] | [.label,.remote,.local,.url] | @tsv' <<<"$plan"
	assert_output "$(printf 'web\t3000\t3000\thttp://127.0.0.1:3000')"
}

@test "build_port_plan: slug mode builds {slug}.localhost for web and {slug}-{label} for others" {
	plan="$(printf 'web\t3000\thttps\ncore-api\t8000\thttp\n' | cs_dev_build_port_plan "feature-x" "")"
	run jq -r '.[] | .url' <<<"$plan"
	assert_line --index 0 "https://feature-x.localhost"
	assert_line --index 1 "https://feature-x-core-api.localhost"
	# ephemeral local ports differ from remote in slug mode
	run jq -r '.[0] | (.local != .remote)' <<<"$plan"
	assert_output "true"
}

@test "build_port_plan: honors CS_DEV_HTTPS_PORT for a non-443 listener" {
	export CS_DEV_HTTPS_PORT=8443
	plan="$(printf 'web\t3000\thttps\n' | cs_dev_build_port_plan "feat" "")"
	run jq -r '.[0].url' <<<"$plan"
	assert_output "https://feat.localhost:8443"
}

@test "build_port_plan: local mode keeps the service's own port (no tunnel remap) but https url" {
	# local_mode=1, not plain: local==remote (service already listens on 127.0.0.1
	# here) yet the url is still the Caddy https://{slug}.localhost.
	plan="$(printf 'web\t3000\thttps\ncore-api\t8000\thttp\n' | cs_dev_build_port_plan "feature-x" "" 1)"
	run jq -r '.[0] | [.remote,.local,.url] | @tsv' <<<"$plan"
	assert_output "$(printf '3000\t3000\thttps://feature-x.localhost')"
	# no ephemeral remap in local mode
	run jq -r '.[1] | (.local == .remote)' <<<"$plan"
	assert_output "true"
}

@test "build_port_plan: does NOT drop the last service when input has no trailing newline" {
	# regression: ports_tsv comes from $(...) (trailing newline stripped) and is
	# piped in with `printf '%s'`. A `while read` without `|| [ -n "$label" ]`
	# skips the final row, silently dropping the LAST declared service (web here).
	plan="$(printf 'backend\t8002\thttp\ncore-api\t8000\thttp\nweb\t3000\thttps' | cs_dev_build_port_plan "feature-x" 1)"
	run jq -r '.[].label' <<<"$plan"
	assert_line --index 0 "backend"
	assert_line --index 1 "core-api"
	assert_line --index 2 "web"
	run jq 'length' <<<"$plan"
	assert_output "3"
}

# --- Caddyfile regen (multi-stack routing) ----------------------------------

@test "caddy_regen: renders one route block per proxied service across sessions" {
	# two concurrent stacks, each with a web route -> distinct subdomains
	planA="$(printf 'web\t3000\thttps\n' | cs_dev_build_port_plan "stack-a" "")"
	planB="$(printf 'web\t3000\thttps\n' | cs_dev_build_port_plan "stack-b" "")"
	sfa="$(cs_dev_session_file "white-monster" "stack-a")"
	sfb="$(cs_dev_session_file "white-monster" "stack-b")"
	cs_dev_session_write "$sfa" "cs-sandbox-a" "white-monster" "codespace/a" "stack/a" "stack-a" 111 1 "$planA"
	cs_dev_session_write "$sfb" "cs-sandbox-b" "white-monster" "codespace/b" "stack/b" "stack-b" 222 1 "$planB"

	cs_dev_caddy_regen
	cf="$(cs_dev_caddyfile)"

	run grep -c 'reverse_proxy' "$cf"
	assert_output "2"
	run grep -F 'https://stack-a.localhost {' "$cf"
	assert_success
	run grep -F 'https://stack-b.localhost {' "$cf"
	assert_success
	# https upstreams get the insecure-skip-verify transport (Next --experimental-https)
	run grep -c 'tls_insecure_skip_verify' "$cf"
	assert_output "2"
}

@test "caddy_regen: plain (proxy=false) sessions contribute no routes" {
	plan="$(printf 'web\t3000\thttps\n' | cs_dev_build_port_plan "plainy" 1)"
	sf="$(cs_dev_session_file "white-monster" "plainy")"
	cs_dev_session_write "$sf" "cs-sandbox-p" "white-monster" "codespace/p" "plainy" "plainy" 333 "" "$plan"
	cs_dev_caddy_regen
	run grep -c 'reverse_proxy' "$(cs_dev_caddyfile)"
	assert_output "0"
}

# --- session file location --------------------------------------------------

@test "session_file: keyed by cleaned host + slug under the dev-sessions cache" {
	run cs_dev_session_file "white-monster" "feature/x"
	[[ "$output" == *"/dev-sessions/white-monster/"* ]]
	# the slug component is cleanpath'd: '/' -> '_' so it stays a single path node
	assert_output --partial "/dev-sessions/white-monster/feature_x.json"
}
