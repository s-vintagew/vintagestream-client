#!/usr/bin/env bash
# Local release APK build (rsyncs out of paths with spaces — Flutter 3.50 quirk).
# Production / OTA builds: prefer GitHub Actions (.github/workflows/release-android.yml).
set -euo pipefail
export JAVA_HOME="${JAVA_HOME:-$HOME/development/jdk-17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/development/gradle-home}"
export PATH="$JAVA_HOME/bin:$HOME/development/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$HOME/development/vintagestream-client"

if [[ ! -f "$ROOT/android/key.properties" ]]; then
  echo "WARNING: android/key.properties missing — APK will be debug-signed (not for OTA)." >&2
fi

mkdir -p "$HOME/development"
rsync -a --delete \
  --exclude '.dart_tool' --exclude 'build' --exclude 'dist' --exclude 'flutter_*.log' \
  --exclude '.git' --exclude '.github' \
  "$ROOT/" "$BUILD/"
cd "$BUILD"
flutter pub get
flutter build apk --release --target-platform=android-arm64
mkdir -p "$ROOT/dist"
cp -f build/app/outputs/flutter-apk/app-release.apk "$ROOT/dist/VintageStream.apk"
echo "APK: $ROOT/dist/VintageStream.apk"
sha256sum "$ROOT/dist/VintageStream.apk"
