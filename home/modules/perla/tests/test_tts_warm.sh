#!/usr/bin/env bash
# Guards for the warm TTS service (spec: docs/superpowers/specs/2026-10-14-tts-latency-design.md).
#
# Brace-matches perla.nix instead of asserting on line numbers, so the test
# tracks the file as it moves. Every assertion here must be observed failing
# against the un-modified module before this suite is trusted.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# tests/ -> perla/ -> modules/. The home-manager module lives at
# home/modules/perla.nix, a sibling of the perla/ payload directory, NOT
# inside it.
NIX="$HERE/../../perla.nix"
PY="$HERE/../perla-companion.py"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; printf '        %s\n' "$2"; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

check_nix() {
  python3 - "$NIX" <<'PY' > "$WORK/nix.txt"
import re, sys
src = open(sys.argv[1]).read()

def block_after(text, marker):
    i = text.find(marker)
    if i < 0:
        return None
    j = text.find("{", i)
    if j < 0:
        return None
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[j:k + 1]
    return None

unit = block_after(src, "systemd.user.services.perla-tts")
print("UNIT_FOUND" if unit else "UNIT_MISSING")
if unit:
    for key in ("Restart = \"on-failure\"", "RestartSec = 5",
                "Install.WantedBy", "default.target", "piper.http_server"):
        print(f"UNIT_HAS[{key}]={key in unit}")
    # The companion must WANT the tts unit, never REQUIRE it: a dead TTS
    # service has to degrade to audio:null, not stop the daemon booting.
    comp = block_after(src, "systemd.user.services.perla-companion") or ""
    print(f"COMP_WANTS={'Wants' in comp and 'perla-tts.service' in comp}")
    print(f"COMP_REQUIRES={'Requires' in comp and 'perla-tts.service' in comp}")
    print(f"COMP_TTS_URL={'PERLA_TTS_URL' in comp}")
    # PERLA_VOICE must reach the daemon; it was silently falling back to the
    # hardcoded default because perla.env is not read by the unit.
    print(f"COMP_VOICE={'PERLA_VOICE=${cfg.voice_model}' in comp}")
PY
  grep -q '^UNIT_FOUND$' "$WORK/nix.txt" \
    && ok "perla.nix defines systemd.user.services.perla-tts" \
    || bad "perla.nix defines systemd.user.services.perla-tts" "unit block not found"
  for key in 'Restart = "on-failure"' 'RestartSec = 5' 'default.target' 'piper.http_server'; do
    if grep -qF "UNIT_HAS[$key]=True" "$WORK/nix.txt"; then
      ok "perla-tts has $key"
    else
      bad "perla-tts has $key" "not present in the unit block"
    fi
  done
  grep -q 'COMP_WANTS=True' "$WORK/nix.txt" \
    && ok "perla-companion Wants perla-tts.service" \
    || bad "perla-companion Wants perla-tts.service" "no Wants on the tts unit"
  grep -q 'COMP_REQUIRES=False' "$WORK/nix.txt" \
    && ok "perla-companion does not Require perla-tts.service" \
    || bad "perla-companion does not Require perla-tts.service" "Requires would make a dead TTS unit fatal"
  grep -q 'COMP_TTS_URL=True' "$WORK/nix.txt" \
    && ok "perla-companion receives PERLA_TTS_URL" \
    || bad "perla-companion receives PERLA_TTS_URL" "env var missing from the unit"
  grep -q 'COMP_VOICE=True' "$WORK/nix.txt" \
    && ok "perla-companion receives PERLA_VOICE (latent-bug fix)" \
    || bad "perla-companion receives PERLA_VOICE (latent-bug fix)" "PERLA_VOICE missing from the unit"
}

check_nix

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1