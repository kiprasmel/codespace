#!/usr/bin/env bash

# Vendor bats-core + helpers into test/vendor/
# Idempotent: clones only what is missing.

set -euo pipefail

DIRNAME="$(dirname "$(realpath "$0")")"
VENDOR_DIR="$DIRNAME/vendor"

BATS_CORE_REF="v1.11.0"
BATS_SUPPORT_REF="v0.3.0"
BATS_ASSERT_REF="v2.1.0"

mkdir -p "$VENDOR_DIR"

clone_pinned() {
	local url="$1" ref="$2" dest="$3"
	if [ -d "$dest/.git" ]; then
		echo "already vendored: $dest"
		return 0
	fi
	echo "cloning $url @ $ref -> $dest"
	git clone --depth 1 --branch "$ref" "$url" "$dest"
}

clone_pinned https://github.com/bats-core/bats-core.git    "$BATS_CORE_REF"    "$VENDOR_DIR/bats-core"
clone_pinned https://github.com/bats-core/bats-support.git "$BATS_SUPPORT_REF" "$VENDOR_DIR/bats-support"
clone_pinned https://github.com/bats-core/bats-assert.git  "$BATS_ASSERT_REF"  "$VENDOR_DIR/bats-assert"

echo
echo "done. run tests with: ./test/run.sh"
