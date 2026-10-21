#!/usr/bin/env bash
# Asserts that the sekaipopSeed logic in home/modules/sekaipop.nix is
# idempotent and never clobbers an existing user file, and that the file list
# exercised here has not drifted from the one in the module.
#
# Run: bash home/modules/sekaipop-seed-test.sh <staged-sekaipop-dir>
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEED_SRC="${1:?usage: sekaipop-seed-test.sh <staged-sekaipop-dir>}"
MODULE="$REPO/home/modules/sekaipop.nix"

SEED_DIR="$(mktemp -d)"
trap 'rm -rf "$SEED_DIR"' EXIT

fails=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$3" "$2"; fails=$((fails + 1)); fi
}

# Run the seeding exactly as home.activation.sekaipopSeed does: guarded install.
seed() {
  for f in "${SEED_FILES[@]}"; do
    [ -e "$SEED_DIR/$f" ] || install -Dm644 "$SEED_SRC/hypr/$f" "$SEED_DIR/$f"
  done
}

# --- read the file list out of the Nix module so the two cannot drift ---
SEED_LINE="$(grep -m1 'for f in custom/env.lua' "$MODULE" || true)"
mapfile -t SEED_FILES < <(
  printf '%s' "$SEED_LINE" \
    | sed 's/.*for f in //; s/;[[:space:]]*do.*//' \
    | tr ' \t' '\n\n' | grep -v '^$'
)

# Fail loudly rather than letting every later assertion pass vacuously on an
# empty list -- which is exactly what happens if the module has no seed loop.
if [ "${#SEED_FILES[@]}" -eq 0 ]; then
  echo "FAIL could not read a seed file list out of $MODULE"
  echo "     the seeding assertions below would all pass vacuously"
  exit 1
fi

check "seed list has 7 files" "${#SEED_FILES[@]}" "7"
for f in custom/env.lua custom/execs.lua custom/general.lua custom/keybinds.lua \
         custom/rules.lua custom/variables.lua sekaipop_overrides.lua; do
  check "module lists $f" "yes" \
    "$(printf '%s\n' "${SEED_FILES[@]}" | grep -qx "$f" && echo yes || echo no)"
done

# --- the module must not seed the static or never-shipped files ---
for f in hyprland.lua hypridle.conf monitors.lua workspaces.lua; do
  check "module does NOT seed $f" "no" \
    "$(printf '%s\n' "${SEED_FILES[@]}" | grep -qx "$f" && echo yes || echo no)"
done

# --- first run creates everything ---
seed
for f in "${SEED_FILES[@]}"; do
  check "created $f" "yes" "$([ -f "$SEED_DIR/$f" ] && echo yes || echo no)"
done

# --- second run changes nothing ---
before=$(cd "$SEED_DIR" && find . -type f -exec md5sum {} \; | sort)
seed
after=$(cd "$SEED_DIR" && find . -type f -exec md5sum {} \; | sort)
check "second run is a no-op" "$before" "$after"

# --- a user edit survives a later seed ---
echo "-- user edit --" >> "$SEED_DIR/sekaipop_overrides.lua"
seed
check "user edit survives re-seed" "1" \
  "$(grep -c 'user edit' "$SEED_DIR/sekaipop_overrides.lua")"

# --- static files are never touched by seeding ---
check "hyprland.lua absent after seeding" "no" \
  "$([ -e "$SEED_DIR/hyprland.lua" ] && echo yes || echo no)"

echo
if [ "$fails" -eq 0 ]; then
  echo "all seeding assertions passed"
else
  echo "$fails FAILED"
  exit 1
fi