#!/usr/bin/env bash

set -xeuo pipefail

PREFIX="${PREFIX:-$HOME/.local}"

# note: since we're creating symlinks, and using DIRNAME,
# helper scripts don't need to be installed into the PREFIX dir,
# as the main scripts will find helper scripts via realpath + DIRNAME.
SCRIPTS="codespace codespace-stack"

for script in $SCRIPTS; do
    ln -sf "$PWD/$script" "$PREFIX/bin/"
done
