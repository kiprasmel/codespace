#!/usr/bin/env bats

# cs_stack__first_error_line — pulls the first ERROR/fatal/err line from a log
# file and prints it to stderr with a caller-supplied indent. Used by the
# failure summary so users see WHY a repo failed without opening the log.

load helpers

setup() {
	common_setup
	source_stack
	OUT="$BATS_TEST_TMPDIR/stderr.out"
}

# helper: capture function's stderr verbatim (preserving leading whitespace,
# which bats `run --separate-stderr` collapses).
capture_stderr() {
	cs_stack__first_error_line "$@" 2>"$OUT"
}

@test "first_error_line: prints first ERROR line indented" {
	log="$BATS_TEST_TMPDIR/r.log"
	cat > "$log" <<'EOF'
==> [prod] cloning git@github.com:sintra-ai/core.git -> ~/codespace/sintra/core
ERROR: Repository not found.
fatal: Could not read from remote repository.
EOF
	capture_stderr "$log" "      "
	[ "$(cat "$OUT")" = "      ERROR: Repository not found." ]
}

@test "first_error_line: matches fatal: when ERROR: absent" {
	log="$BATS_TEST_TMPDIR/r.log"
	cat > "$log" <<'EOF'
some noise
fatal: not a git repository
EOF
	capture_stderr "$log" "  "
	[ "$(cat "$OUT")" = "  fatal: not a git repository" ]
}

@test "first_error_line: matches err: prefix" {
	log="$BATS_TEST_TMPDIR/r.log"
	echo 'err: cannot resolve config' > "$log"
	capture_stderr "$log" "  "
	[ "$(cat "$OUT")" = "  err: cannot resolve config" ]
}

@test "first_error_line: no matching line -> silent, exit 0" {
	log="$BATS_TEST_TMPDIR/r.log"
	cat > "$log" <<'EOF'
just some output
nothing wrong here
EOF
	capture_stderr "$log" "  "
	[ ! -s "$OUT" ]
}

@test "first_error_line: missing log file -> silent, exit 0" {
	capture_stderr "$BATS_TEST_TMPDIR/no-such-log" "  "
	[ ! -s "$OUT" ]
}

@test "first_error_line: only the first matching line is printed" {
	log="$BATS_TEST_TMPDIR/r.log"
	cat > "$log" <<'EOF'
ERROR: first
ERROR: second
fatal: third
EOF
	capture_stderr "$log" ""
	[ "$(cat "$OUT")" = "ERROR: first" ]
}

@test "first_error_line: exit 0 on success and silence" {
	# regression: helper must not return non-zero (would propagate under set -e
	# in the caller's summarize loop).
	log="$BATS_TEST_TMPDIR/r.log"
	echo 'no errors here' > "$log"
	cs_stack__first_error_line "$log" "  "
	# explicitly assert via direct call (run/set -e behaviour intact)
	cs_stack__first_error_line "$log" "  " || fail "helper returned non-zero"
}
