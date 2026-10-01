#!/usr/bin/env bash
# Guards the key OpenCode uses for MCP server environment variables.
#
# OpenCode's McpLocalConfig type declares `environment?: {...}`. The `env` key
# belongs to the *lsp* config type. Declaring `env` on an mcp server is silently
# ignored — no validation error — so every env var the server needs is dropped
# and the process falls back to its own defaults.
#
# That is how PERLA_TIER went missing: the file MCP defaulted it to 0, the
# daemon's `if tier in (1, 2)` never matched, no staged-file record was ever
# written, and send_file silently produced "file": null in the web UI.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# tests/ -> perla/ -> modules/ -> home/ -> repo root
REPO="$HERE/../../../.."
T1="$REPO/home/modules/perla.nix"
T2="$REPO/home/modules/perla/opencode-t2-config.nix"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

for f in "$T1" "$T2"; do
  label=$(basename "$f")
  [ -f "$f" ] || { bad "$label exists" "not found: $f"; continue; }

  # Any `env = {` that belongs to an mcp server is wrong; the enclosing server
  # name is the nearest lower-indent `name = {` above it.
  offenders=$(python3 - "$f" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
bad = []
for i, l in enumerate(lines):
    m = re.match(r"^(\s*)env = \{", l)
    if not m:
        continue
    indent = len(m.group(1))
    # Walk back to the nearest lower-indent key: that names the server.
    for j in range(i - 1, -1, -1):
        k = re.match(r"^(\s*)([A-Za-z_-][\w-]*)\s*=\s*\{", lines[j])
        if k and len(k.group(1)) < indent:
            if k.group(2) in ("mcp", "lsp", "formatter", "provider"):
                break
            bad.append((i + 1, k.group(2)))
            break
for line_no, server in bad:
    print(f"{line_no}:{server}")
PY
)
  if [ -z "$offenders" ]; then
    ok "$label: no mcp server declares 'env'"
  else
    bad "$label: no mcp server declares 'env'" "offending lines: $(echo "$offenders" | tr '\n' ' ')"
  fi

  # And positively: the mcp blocks must actually pass PERLA_TIER through.
  if grep -q "environment = {" "$f"; then
    ok "$label: uses 'environment' for mcp env vars"
  else
    bad "$label: uses 'environment' for mcp env vars" "no 'environment = {' found"
  fi
done

# The end-to-end consequence, asserted where it is actually observable: the
# deployed OpenCode configs must not carry a bare `env` key on an mcp server.
echo
echo "=== the deployed configs (skipped if the tier dir is absent) ==="
for d in /run/user/$UID/perla/t1-config/opencode/opencode.json \
         /run/user/$UID/perla/t2-config/opencode/opencode.json; do
  [ -f "$d" ] || { echo "  SKIP  $d not present"; continue; }
  res=$(python3 - "$d" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
mcp = d.get("mcp") or {}
wrong = [n for n, c in mcp.items() if isinstance(c, dict) and "env" in c and "environment" not in c]
tiers = {n: (c.get("environment") or {}).get("PERLA_TIER") for n, c in mcp.items() if isinstance(c, dict)}
print(("OK" if not wrong else "BAD:" + ",".join(sorted(wrong))) + "|" + json.dumps(tiers))
PY
)
  verdict="${res%%|*}"; tiers="${res#*|}"
  if [ "$verdict" = "OK" ]; then
    ok "$(basename "$(dirname "$d")"): no mcp server uses a bare 'env' key"
  else
    bad "$(basename "$(dirname "$d")"): no mcp server uses a bare 'env' key" "$verdict"
  fi
  echo "        PERLA_TIER per server: $tiers"
done

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
