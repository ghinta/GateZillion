#!/usr/bin/env bash
# Fast loop: rebuild the place and run the unit/integration tests.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ -d .tools/bin ]; then
	export PATH="$PWD/.tools/bin:$PATH"
fi

mkdir -p build
rojo build default.project.json -o build/GateZillion.rbxl >/dev/null
lune run tests/runner.luau build/GateZillion.rbxl
