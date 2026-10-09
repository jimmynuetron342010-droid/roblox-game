#!/usr/bin/env bash
# Renders weapon screenshots (held by an R15 rig + standalone) into tests/renders/out.
# Needs: lune, rojo, node, and the npm packages `three` + `playwright` (RENDER_DEPS=<node_modules>).
# Usage: scripts/render.sh [weaponIdFilter] [PoseName]
set -euo pipefail
cd "$(dirname "$0")/.."
rojo sourcemap default.project.json --output sourcemap.json >/dev/null
lune run tests/render/export_weapons.luau "${1:-}" "${2:-Idle}"
node tests/render/render.mjs tests/renders/out/scenes.json tests/renders/out
