#!/usr/bin/env bash
# Builds a test APK and publishes it as a GitHub pre-release. Installed test
# builds see it and offer "Update" (the user confirms the install).
#
#   API_BASE_URL=http://192.168.50.6:8080 NOTES="What changed" scripts/publish-test-build.sh
#
# Bump `version:` in app/pubspec.yaml first: the number after "+" must grow.
set -euo pipefail

: "${API_BASE_URL:?Set API_BASE_URL, e.g. http://192.168.50.6:8080 or https://api.example.com}"
NOTES=${NOTES:-"Test build."}

cd "$(dirname "$0")/../app"
full=$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1 \2/p' pubspec.yaml)
version=${full% *}
build=${full#* }
tag="v${version}-b${build}"

if gh release view "$tag" >/dev/null 2>&1; then
  echo "Release $tag already exists: bump the build number in pubspec.yaml." >&2
  exit 1
fi

# Profile mode: compiled ahead of time (fast, about 20 MB per chip) yet still a
# test build (home-network HTTP and self-update, see android/app/src/profile).
flutter build apk --profile --split-per-abi --dart-define=API_BASE_URL="$API_BASE_URL"
apks=()
for abi in arm64-v8a armeabi-v7a x86_64; do
  out="build/study-assistant-${version}-b${build}-${abi}.apk"
  cp "build/app/outputs/flutter-apk/app-${abi}-profile.apk" "$out"
  apks+=("$out")
done

git push --quiet origin HEAD
gh release create "$tag" "${apks[@]}" \
  --prerelease \
  --target "$(git rev-parse HEAD)" \
  --title "Test build ${version} (${build})" \
  --notes "$NOTES"
echo "Published $tag"
