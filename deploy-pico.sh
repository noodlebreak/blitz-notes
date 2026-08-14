#!/usr/bin/env bash
# Build a minified static copy of Blitz Notes and rsync it to pico.sh pages.
# Usage:
#   ./deploy-pico.sh              minify + deploy
#   ./deploy-pico.sh --build-only minify only (no SSH / rsync)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/index.html"
DIST="$ROOT/dist"
OUT="$DIST/index.html"
SSH_KEY="${PICO_SSH_IDENTITY:-$HOME/.ssh/ashish-cmm-macbookm4pro}"
PROJECT="${PICO_PROJECT:-blitz-notes}"
PICO_USER="${PICO_USER:-noodlebreak}"
BUILD_ONLY=0
RSYNC_SSH="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes"

if [[ "${1:-}" == "--build-only" ]]; then
  BUILD_ONLY=1
fi

run() {
  echo
  echo "+ $*"
  "$@"
}

bytes() {
  wc -c <"$1" | tr -d ' '
}

human() {
  python3 -c 'import sys; n=int(sys.argv[1])
u=["B","KB","MB","GB"]; i=0
x=float(n)
while x>=1024 and i<len(u)-1:
  x/=1024; i+=1
print(f"{n} bytes" if i==0 else f"{n} bytes ({x:.1f} {u[i]})")' "$1"
}

gzip_bytes() {
  python3 -c 'import gzip, pathlib, sys; print(len(gzip.compress(pathlib.Path(sys.argv[1]).read_bytes(), 9)))' "$1"
}

echo "Blitz Notes → pico.sh"
echo "repo:    $ROOT"
echo "source:  $SRC"
echo "dist:    $OUT"
echo "project: $PROJECT"
echo "key:     $SSH_KEY"
if [[ "$BUILD_ONLY" -eq 1 ]]; then
  echo "mode:    build-only (skip rsync)"
else
  echo "mode:    minify + rsync"
fi

if [[ ! -f "$SRC" ]]; then
  echo "error: missing $SRC" >&2
  exit 1
fi
if ! command -v npx >/dev/null 2>&1; then
  echo "error: npx is required (html-minifier-terser is invoked via npx, not added as a project dependency)" >&2
  exit 1
fi
if [[ "$BUILD_ONLY" -eq 0 && ! -f "$SSH_KEY" ]]; then
  echo "error: SSH key not found: $SSH_KEY" >&2
  exit 1
fi

preflight_pico() {
  echo
  echo "+ ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes pico.sh help"
  local out rc=0
  out="$(ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes pico.sh help 2>&1)" || rc=$?
  echo "$out"
  if [[ "$rc" -eq 0 ]]; then
    return 0
  fi
  echo >&2
  if echo "$out" | grep -q "pubkey not found"; then
    echo "error: pico.sh does not know this SSH key, so pgs.sh rsync cannot authenticate." >&2
    echo "This is the GitHub personal key (${SSH_KEY})." >&2
    echo >&2
    echo "The live url-db site is on the existing 'noodlebreak' pico account, which was" >&2
    echo "created with a different key (not on this Mac)." >&2
    echo >&2
    echo "From a machine that can already: ssh pico.sh" >&2
    echo "  add this pubkey: ssh pico.sh  → Manage Keys  (press c)" >&2
    echo "  or append it to authorized_keys and rsync it back to pico.sh:/" >&2
    echo >&2
    echo "This Mac's pubkey to add:" >&2
    cat "${SSH_KEY}.pub" >&2
  else
    echo "error: pico.sh SSH preflight failed (exit ${rc})" >&2
  fi
  exit 1
}

run mkdir -p "$DIST"
run npx --yes html-minifier-terser@7 "$SRC" \
  --collapse-whitespace \
  --remove-comments \
  --collapse-boolean-attributes \
  --remove-redundant-attributes \
  --remove-script-type-attributes \
  --remove-style-link-type-attributes \
  --minify-css true \
  --minify-js '{"compress":true,"mangle":{"reserved":["showList"]}}' \
  -o "$OUT"

SRC_BYTES="$(bytes "$SRC")"
OUT_BYTES="$(bytes "$OUT")"
SAVED="$((SRC_BYTES - OUT_BYTES))"
GZ_BYTES="$(gzip_bytes "$OUT")"

echo
echo "--- build ---"
echo "source:    $(human "$SRC_BYTES")"
echo "minified:  $(human "$OUT_BYTES")"
echo "saved:     $(human "$SAVED")"
echo "gzip (estimate only; pico stores the uncompressed file): $(human "$GZ_BYTES")"

if [[ "$BUILD_ONLY" -eq 1 ]]; then
  echo
  echo "--- result ---"
  echo "built $OUT"
  echo "did not deploy"
  exit 0
fi

preflight_pico

run rsync --delete -rv -e "$RSYNC_SSH" "$DIST/" "pgs.sh:/${PROJECT}/"

echo
echo "+ $RSYNC_SSH pgs.sh stats"
$RSYNC_SSH pgs.sh stats || true

echo
echo "+ $RSYNC_SSH pgs.sh ls"
$RSYNC_SSH pgs.sh ls || true

LIVE="https://${PICO_USER}-${PROJECT}.pgs.sh/"
echo
echo "--- result ---"
echo "minified ${OUT_BYTES} bytes from ${SRC_BYTES} (saved ${SAVED})"
echo "uploaded dist/ → pgs.sh:/${PROJECT}/"
echo "live: ${LIVE}"
echo "identity: $SSH_KEY"
