#!/usr/bin/env bash

set -xeuo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
EXE="codespace"

ln -s "$PWD/$EXE" "$PREFIX/bin/"
