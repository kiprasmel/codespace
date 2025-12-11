#!/usr/bin/env bash

set -xeuo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
SCRIPTS="codespace codespace-stack"

for script in $SCRIPTS; do
    ln -sf "$PWD/$script" "$PREFIX/bin/"
done
