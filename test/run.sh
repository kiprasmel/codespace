#!/usr/bin/env bash

# Run the bats test suite. Arguments are forwarded to bats.
#   ./test/run.sh                        # run all tests (parallel, JOBS=$(nproc))
#   ./test/run.sh -f resolve_post_create # filter by name
#   ./test/run.sh test/foo.bats          # specific file
#   JOBS=1 ./test/run.sh                 # serial
#   JOBS=4 ./test/run.sh                 # override parallelism

set -euo pipefail

DIRNAME="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$DIRNAME")"
VENDOR_DIR="$DIRNAME/vendor"
BATS_BIN="$VENDOR_DIR/bats-core/bin/bats"
BATS_PARALLEL_WRAPPER="$DIRNAME/bats-parallel"
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

default_jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"
jobs="${JOBS:-$default_jobs}"

bats_args=()
mode="serial"
# Interactive TTY: pretty re-renders progress, and our parallel wrapper drops
# bats' --keep-order so results stream as files finish (order not guaranteed).
# Non-TTY (CI/pipes): keep stock parallel + ordered TAP for stable logs.
tty_out=0
if [ -t 1 ]; then
	tty_out=1
	bats_args+=(--pretty)
fi

if [ "$jobs" = 1 ]; then
	:& # serial
elif [ ! -x "$GNU_PARALLEL" ]; then
	>&2 echo "note: GNU parallel not found; running serially (./test/setup.sh to install)"
	jobs=1
elif [ "$tty_out" -eq 1 ] && [ -x "$BATS_PARALLEL_WRAPPER" ]; then
	export BATS_GNU_PARALLEL="$GNU_PARALLEL"
	bats_args+=(-j "$jobs" --parallel-binary-name "$BATS_PARALLEL_WRAPPER")
	mode="parallel"
else
	bats_args+=(-j "$jobs" --parallel-binary-name "$GNU_PARALLEL")
	mode="parallel"
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
