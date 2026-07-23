#!/usr/bin/env bash

# Run the bats test suite. Arguments are forwarded to bats.
#   ./test/run.sh                        # run all tests
#   ./test/run.sh -f resolve_post_create # filter by name
#   ./test/run.sh test/foo.bats          # specific file
#   SERIAL=1 ./test/run.sh               # force serial (no GNU parallel)

set -euo pipefail

DIRNAME="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$DIRNAME")"
VENDOR_DIR="$DIRNAME/vendor"
BATS_BIN="$VENDOR_DIR/bats-core/bin/bats"
GNU_PARALLEL="$(brew --prefix parallel 2>/dev/null)/bin/parallel"

if [ ! -x "$BATS_BIN" ]; then
	>&2 echo "err: bats not vendored. run: ./test/setup.sh"
	exit 1
fi

# make the working-tree scripts resolvable as `codespace`, `codespace-stack`
export PATH="$REPO_ROOT:$PATH"
export REPO_ROOT

if [ $# -eq 0 ]; then
	set -- "$DIRNAME"
fi

bats_args=()
mode="serial"
jobs=""
if [ "${SERIAL:-}" = 1 ]; then
	>&2 echo "note: SERIAL=1; running serially"
elif [ -x "$GNU_PARALLEL" ]; then
	jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || true)"
	if [ -n "${jobs:-}" ] && [ "$jobs" -gt 1 ] 2>/dev/null; then
		bats_args=(-j "$jobs" --parallel-binary-name "$GNU_PARALLEL")
		mode="parallel"
	fi
else
	>&2 echo "note: GNU parallel not found; running serially (./test/setup.sh to install)"
fi

# wall-clock only — zsh/bash `time` also prints summed CPU across cores, which
# makes parallel look slower even when wall time is much lower.
start="$(date +%s)"
set +e
"$BATS_BIN" "${bats_args[@]}" "$@"
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
if [ "$mode" = parallel ]; then
	>&2 echo "note: finished in ${elapsed}s wall ($mode, -j $jobs)"
else
	>&2 echo "note: finished in ${elapsed}s wall ($mode)"
fi
exit "$rc"
