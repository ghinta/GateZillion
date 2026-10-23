#!/usr/bin/env bash
# Runs every quality gate: format, lint, build, type check and tests.
# Tools come from .tools/bin (scripts/install-tools.sh) or from PATH (e.g. rokit).
set -euo pipefail

cd "$(dirname "$0")/.."
if [ -d .tools/bin ]; then
	export PATH="$PWD/.tools/bin:$PATH"
fi

# Roblox API type definitions matching the pinned luau-lsp version.
LUAU_LSP_VERSION=1.55.0
if [ ! -f globalTypes.d.luau ]; then
	curl -fsSL --retry 3 -o globalTypes.d.luau \
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LUAU_LSP_VERSION}/scripts/globalTypes.d.luau"
fi

echo "== Format (StyLua)"
stylua --check src tests

echo "== Lint (Selene)"
selene src tests

echo "== Build (Rojo)"
mkdir -p build
rojo build default.project.json -o build/GateZillion.rbxl
rojo sourcemap default.project.json -o sourcemap.json

echo "== Type check (luau-lsp, --!strict)"
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src

echo "== Tests (Lune)"
lune run tests/runner.luau build/GateZillion.rbxl
