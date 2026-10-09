#!/usr/bin/env bash
# Static checks: Luau type analysis (luau-lsp + Rojo sourcemap), Selene lint, StyLua format check.
# Tool locations can be overridden with env vars. See docs/TESTING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLS="${SOUL_TOOLS_DIR:-$HOME/.soul-eater-tools}"
LUAU_LSP="${LUAU_LSP:-$(command -v luau-lsp || echo "$TOOLS/luau-lsp")}"
ROBLOX_DEFS="${ROBLOX_DEFS:-$TOOLS/globalTypes.d.luau}"

status=0

echo "== rojo sourcemap"
rojo sourcemap default.project.json --output sourcemap.json

echo "== luau-lsp analyze"
if [[ -x "$LUAU_LSP" && -f "$ROBLOX_DEFS" ]]; then
	"$LUAU_LSP" analyze --platform=roblox --sourcemap=sourcemap.json --definitions="@roblox=$ROBLOX_DEFS" \
		--base-luaurc=.luaurc src || status=1
else
	echo "skipped (set LUAU_LSP and ROBLOX_DEFS, see docs/TESTING.md)"
fi

echo "== selene"
if [[ ! -f roblox.yml ]]; then
	selene generate-roblox-std
fi
selene src tests tools || status=1

echo "== stylua --check"
stylua --check src tests tools || status=1

exit $status
