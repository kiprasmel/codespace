#!/usr/bin/env bash

# Run the bats test suite. Arguments are forwarded to bats.
#   ./test/run.sh                        # run all tests
#   ./test/run.sh -f resolve_post_create # filter by name
#   ./test/run.sh test/foo.bats          # specific file

set -euo pipefail

DIRNAME="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$DIRNAME")"
VENDOR_DIR="$DIRNAME/vendor"
BATS_BIN="$VENDOR_DIR/bats-core/bin/bats"

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

exec "$BATS_BIN" "$@"
