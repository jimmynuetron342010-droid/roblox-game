#!/usr/bin/env bash
# Runs the Lune test-suite against the real game modules (via the Rojo sourcemap).
# Usage: scripts/test.sh [spec-name-filter]
set -euo pipefail
cd "$(dirname "$0")/.."
rojo sourcemap default.project.json --output sourcemap.json >/dev/null
lune run tests/run.luau "$@"
