#!/usr/bin/env bash
# Local helper: build APK and (optionally) publish to GitHub Releases.
# Prefer CI on push to main for production. This script is for manual / emergency publishes.
#
# Release tag MUST match pubspec version, e.g. 0.2.0+2
#
# Env:
#   UPDATE_REPO=s-vintagew/vintagestream-client   (default)
#   UPDATE_NOTES='What changed'
#   SKIP_GITHUB=1                                 (build only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE_REPO="${UPDATE_REPO:-s-vintagew/vintagestream-client}"
NOTES="${UPDATE_NOTES:-}"
SKIP_GITHUB="${SKIP_GITHUB:-0}"

"$ROOT/scripts/build_apk.sh"

APK="$ROOT/dist/VintageStream.apk"
if [[ ! -f "$APK" ]]; then
  echo "Missing APK at $APK" >&2
  exit 1
fi

VERSION_LINE="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -n1 | awk '{print $2}')"
if [[ -z "$VERSION_LINE" || "$VERSION_LINE" != *+* ]]; then
  echo "Could not parse version from pubspec.yaml (expected name+code like 0.2.0+2)" >&2
  exit 1
fi

TAG="$VERSION_LINE"
NAME="${TAG%%+*}"
CODE="${TAG##*+}"
SHA256="$(sha256sum "$APK" | awk '{print $1}')"
MANIFEST="$ROOT/dist/latest.json"
cat > "$MANIFEST" <<EOF
{
  "versionName": "$NAME",
  "versionCode": $CODE,
  "sha256": "$SHA256",
  "notes": "${NOTES:-VintageStream $TAG}",
  "mandatory": false
}
EOF

echo "Built $TAG"
echo "SHA256 $SHA256"
echo "APK    $APK"

if [[ "$SKIP_GITHUB" == "1" ]]; then
  echo "SKIP_GITHUB=1 — not uploading. Create a Release tagged $TAG and attach the APK + latest.json."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Create a Release manually:" >&2
  echo "  tag $TAG on $UPDATE_REPO, attach $APK and $MANIFEST" >&2
  exit 1
fi

if gh release view "$TAG" --repo "$UPDATE_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists on $UPDATE_REPO — uploading/replacing assets"
  gh release upload "$TAG" "$APK" "$MANIFEST" --repo "$UPDATE_REPO" --clobber
else
  ARGS=(release create "$TAG" "$APK" "$MANIFEST" --repo "$UPDATE_REPO" --title "$TAG")
  if [[ -n "$NOTES" ]]; then
    ARGS+=(--notes "$NOTES")
  else
    ARGS+=(--generate-notes)
  fi
  gh "${ARGS[@]}"
fi

echo "Published https://github.com/$UPDATE_REPO/releases/tag/$TAG"
