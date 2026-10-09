#!/usr/bin/env bash
# Headless play-test of the whole game on strict mock Instances (validated against the Roblox API
# dump, so invalid properties / methods / value types fail exactly like in Roblox):
#   1. server: boots all 16 services, builds the map, spawns enemies, then plays a session as a
#      client (create student, roll origin, equip, fight, kill, rewards, abilities, rejoin + save)
#   2. client 3D: every weapon attack effect, impact, ability visual and the animator
#   3. client UI: walks through every screen on desktop / laptop / tablet / phone profiles
# With RENDER_DEPS (node_modules containing playwright) and CHROMIUM_PATH set, every UI step is
# also rendered to PNG and checked for text overflow / off-screen elements.
# Usage: scripts/playtest.sh [profile...]   (profiles: desktop laptop tablet phone)
set -euo pipefail
cd "$(dirname "$0")/.."
rojo sourcemap default.project.json --output sourcemap.json >/dev/null
profiles=("$@")
if [[ ${#profiles[@]} -eq 0 ]]; then
	profiles=(desktop laptop tablet phone)
fi
status=0
lune run tests/server/run_server.luau || status=1
lune run tests/ui/run_vfx.luau || status=1
for profile in "${profiles[@]}"; do
	if ! lune run tests/ui/run_ui.luau "$profile" tests/renders/out/ui; then
		status=1
		continue
	fi
	if [[ -n "${RENDER_DEPS:-}" ]]; then
		node tests/ui/render_ui.mjs "tests/renders/out/ui/$profile" --annotate | tail -n 1
		if grep -q '"kind"' "tests/renders/out/ui/$profile/report.json"; then
			echo "layout issues in $profile — see tests/renders/out/ui/$profile/report.json"
			status=1
		fi
	fi
done
exit $status
