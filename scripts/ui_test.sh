#!/usr/bin/env bash
# Headless client run: executes every VFX effect / ability visual / the animator on strict mock
# Instances, then the UI walkthrough boots the real client UI against a simulated server on several device
# profiles, plays through every screen, and fails on any runtime error, invalid Roblox property
# access or failed expectation. If RENDER_DEPS (node_modules with playwright) and CHROMIUM_PATH are
# set, it also renders every step to PNG and reports text overflow / off-screen elements.
# Usage: scripts/ui_test.sh [profile...]   (profiles: desktop laptop tablet phone)
set -euo pipefail
cd "$(dirname "$0")/.."
rojo sourcemap default.project.json --output sourcemap.json >/dev/null
profiles=("$@")
if [[ ${#profiles[@]} -eq 0 ]]; then
	profiles=(desktop laptop tablet phone)
fi
status=0
# 3D systems first: all weapon effects, ability visuals and the animator on strict mocks.
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
