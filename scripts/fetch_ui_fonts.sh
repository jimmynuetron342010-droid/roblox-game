#!/usr/bin/env bash
# Downloads open-licensed stand-ins for the UI fonts so UI snapshots render with similar metrics:
#   Bangers (OFL), Permanent Marker (Apache 2.0), Montserrat 500/700 (OFL) for GothamSSm.
# Saved to tests/ui/fonts (git-ignored). render_ui.mjs reads UI_FONTS or that folder.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${UI_FONTS:-tests/ui/fonts}"
mkdir -p "$out"
ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"
fetch() { # family-query  file-prefix
	local css
	css=$(curl -fsS -A "$ua" "https://fonts.googleapis.com/css2?family=$1&display=swap")
	# Keep the latin subset of every weight.
	python3 - "$css" "$out" "$2" <<'PY'
import re, subprocess, sys
css, out, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
for subset, block in re.findall(r"/\* (\S+) \*/\s*@font-face\s*{([^}]*)}", css):
    if subset != "latin":
        continue
    url = re.search(r"url\((https://[^)]+)\)", block).group(1)
    weight = re.search(r"font-weight:\s*(\d+)", block).group(1)
    subprocess.run(["curl", "-fsS", "-o", f"{out}/{prefix}-{weight}.woff2", url], check=True)
PY
}
fetch "Bangers" "Bangers"
fetch "Permanent+Marker" "PermanentMarker"
fetch "Montserrat:wght@500;700" "Montserrat"
ls -1 "$out"
