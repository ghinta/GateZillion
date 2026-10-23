#!/usr/bin/env bash
# Installs the pinned toolchain into .tools/bin (Linux x86_64). Used by CI.
# Locally, `rokit install` (see rokit.toml) is the cross-platform alternative; keep versions in sync.
set -euo pipefail

ROJO_VERSION=7.5.1
STYLUA_VERSION=2.1.0
SELENE_VERSION=0.29.0
LUNE_VERSION=0.10.2
LUAU_LSP_VERSION=1.55.0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.tools/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN"

fetch() {
	local name="$1" url="$2"
	curl -fsSL --retry 3 -o "$TMP/$name.zip" "$url"
	unzip -o -q "$TMP/$name.zip" -d "$TMP/$name"
	install -m 0755 "$(find "$TMP/$name" -type f -name "$name" | head -n 1)" "$BIN/$name"
}

fetch rojo "https://github.com/rojo-rbx/rojo/releases/download/v${ROJO_VERSION}/rojo-${ROJO_VERSION}-linux-x86_64.zip"
fetch stylua "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-x86_64.zip"
fetch selene "https://github.com/Kampfkarren/selene/releases/download/${SELENE_VERSION}/selene-${SELENE_VERSION}-linux.zip"
fetch lune "https://github.com/lune-org/lune/releases/download/v${LUNE_VERSION}/lune-${LUNE_VERSION}-linux-x86_64.zip"
fetch luau-lsp "https://github.com/JohnnyMorganz/luau-lsp/releases/download/${LUAU_LSP_VERSION}/luau-lsp-linux-x86_64.zip"

echo "Installed into $BIN:"
for tool in rojo stylua selene lune luau-lsp; do
	"$BIN/$tool" --version
done
