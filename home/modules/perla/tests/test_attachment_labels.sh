#!/usr/bin/env bash
# Tests the attachment labelling helpers.
#
# The rule these encode: TYPE is always derivable (from the filename extension),
# and SIZE is only ever shown when it is actually known. File size and mime are
# never persisted — a queued item has the real File, but a sent attachment
# carries only {filename, url} and a history replay only {filename, id} — so
# guessing a size would put a number on screen that is simply wrong.
#
# The functions are extracted from the real source structurally and run in node.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
JS="$HERE/../perla-companion.js"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

python3 - "$JS" "$WORK/helpers.js" <<'PY'
import sys
src = open(sys.argv[1]).read()
lines = src.split("\n")
def block(sig):
    s = next(k for k, l in enumerate(lines) if l.strip().startswith("function " + sig))
    ind = len(lines[s]) - len(lines[s].lstrip()); e = s
    for k in range(s + 1, len(lines)):
        l = lines[k]
        if l.strip() and (len(l) - len(l.lstrip())) <= ind:
            e = k; break
    return "\n".join(lines[s:e + 1])
need = ["typeFromFilename", "formatBytes", "attachmentMetaLine"]
missing = [n for n in need if ("function " + n + "(") not in src]
if missing:
    print("MISSING:" + ",".join(missing)); sys.exit(3)
i = src.find("    const ATTACHMENT_TYPES = {")
j = src.find("};", i) + 2
if i == -1:
    print("MISSING:ATTACHMENT_TYPES"); sys.exit(3)
open(sys.argv[2], "w").write(src[i:j] + "\n" + "\n".join(block(n) for n in need))
PY
rc=$?
if [ "$rc" = 3 ]; then
  bad "attachment helpers exist in the source" "$(cat "$WORK/helpers.js" 2>/dev/null; echo 'not found')"
  echo; echo "=================================="; echo "  $pass passed, $fail failed"; exit 1
fi
ok "attachment helpers exist in the source"

cat > "$WORK/run.js" <<'JS'
const fs = require("fs");
process.stdout.write("LOADING\n");
const mod = eval(fs.readFileSync(process.argv[2], "utf8") +
  "\n;({ typeFromFilename, formatBytes, attachmentMetaLine })");
process.stdout.write("READY\n");

const results = [];
const t = (name, actualOrFn, expected) => {
  let actual, err = null;
  try { actual = (typeof actualOrFn === "function") ? actualOrFn() : actualOrFn; }
  catch (e) { err = e; }
  const ok = !err && JSON.stringify(actual) === JSON.stringify(expected);
  results.push({ name, ok, got: err ? "threw: " + err : JSON.stringify(actual),
                 want: JSON.stringify(expected) });
};

// --- typeFromFilename: known extensions map to readable labels
t("png -> PNG", mod.typeFromFilename("a.png"), "PNG");
t("jpg -> JPG", mod.typeFromFilename("a.jpg"), "JPG");
t("jpeg -> JPG (both spellings)", mod.typeFromFilename("a.jpeg"), "JPG");
t("pdf -> PDF", mod.typeFromFilename("sales-dashboard.pdf"), "PDF");
t("tsx -> TypeScript", mod.typeFromFilename("message-renderer.tsx"), "TypeScript");
t("ts -> TypeScript", mod.typeFromFilename("x.ts"), "TypeScript");
t("py -> Python", mod.typeFromFilename("x.py"), "Python");
t("md -> Markdown", mod.typeFromFilename("notes.md"), "Markdown");
t("json -> JSON", mod.typeFromFilename("x.json"), "JSON");
t("uppercase extension is lowercased first", mod.typeFromFilename("A.PNG"), "PNG");
t("mixed case extension", mod.typeFromFilename("Photo.JpEg"), "JPG");

// --- typeFromFilename: the awkward cases
t("unknown extension is uppercased, not dropped", mod.typeFromFilename("a.zzz"), "ZZZ");
t("no extension -> File", mod.typeFromFilename("README"), "File");
t("dotfile is not an extension", mod.typeFromFilename(".gitignore"), "File");
t("trailing dot -> File", mod.typeFromFilename("weird."), "File");
t("empty filename -> File", mod.typeFromFilename(""), "File");
t("null filename -> File", mod.typeFromFilename(null), "File");
t("only the LAST extension counts (.gz wins, not .tar)", mod.typeFromFilename("archive.tar.gz"), "Gzip");
t("dotted name with a real extension", mod.typeFromFilename("v1.2.3-report.pdf"), "PDF");

// --- formatBytes: an UNKNOWN size must produce nothing, never a wrong number
t("null size -> empty", mod.formatBytes(null), "");
t("undefined size -> empty", mod.formatBytes(undefined), "");
t("NaN -> empty", mod.formatBytes(NaN), "");
t("negative -> empty", mod.formatBytes(-1), "");
t("0 bytes", mod.formatBytes(0), "0 B");
t("512 bytes", mod.formatBytes(512), "512 B");
t("1023 bytes stays in B", mod.formatBytes(1023), "1023 B");
t("1024 -> 1 KB", mod.formatBytes(1024), "1 KB");
t("820 KB matches the reference's format", mod.formatBytes(820 * 1024), "820 KB");
t("11 MB has no decimal", mod.formatBytes(11 * 1024 * 1024), "11 MB");
t("9.4 MB keeps one decimal", mod.formatBytes(Math.round(9.4 * 1024 * 1024)), "9.4 MB");
t("1 GB", mod.formatBytes(1024 * 1024 * 1024), "1 GB");
t("beyond TB does not crash", typeof mod.formatBytes(1024 ** 5), "string");

// --- attachmentMetaLine: the second line
t("type only when size is unknown", mod.attachmentMetaLine("a.pdf", null), "PDF");
t("type only when size is undefined", mod.attachmentMetaLine("a.pdf", undefined), "PDF");
t("type and size when known", mod.attachmentMetaLine("a.pdf", 2.4 * 1024 * 1024), "PDF · 2.4 MB");
t("image card line", mod.attachmentMetaLine("workspace-photo.png", 820 * 1024), "PNG · 820 KB");
t("a 0-byte file still shows its size", mod.attachmentMetaLine("empty.txt", 0), "Text · 0 B");
t("never emits a bare separator", () => !/^ · | ·$/.test(mod.attachmentMetaLine("a.zzz", null)), true);

let failed = 0;
for (const r of results) {
  process.stdout.write((r.ok ? "PASS" : "FAIL") + "\t" + r.name +
    (r.ok ? "" : "\n\tgot  " + r.got + "\n\twant " + r.want) + "\n");
  if (!r.ok) failed++;
}
process.stdout.write("TOTAL\t" + results.length + "\t" + failed + "\n");
JS

out=$(node "$WORK/run.js" "$WORK/helpers.js" 2>&1)
if ! grep -q "^READY" <<<"$out"; then
  bad "the helpers evaluate in node" "node failed before READY: $(head -4 <<<"$out" | tr '\n' ' ')"
else
  ok "the helpers evaluate in node"
  tab=$'\t'
  n=0
  while IFS="$tab" read -r status name rest; do
    case "$status" in
      PASS) ok "$name"; n=$((n + 1)) ;;
      FAIL) bad "$name" "$(awk -v nm="$name" -F'\t' '$1=="FAIL" && $2==nm {getline g; getline w; print g " " w}' <<<"$out")" ;;
      TOTAL|READY|LOADING) : ;;
    esac
  done <<<"$out"
  if [ "$n" -lt 30 ]; then
    bad "all assertions ran" "only $n of the expected assertions reported — the test is not checking what it claims"
  else
    ok "all assertions ran ($n)"
  fi
fi

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
