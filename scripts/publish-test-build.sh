#!/usr/bin/env bash
# Builds a test APK and publishes it as a GitHub pre-release. Installed test
# builds see it and offer "Update" (the user confirms the install).
#
#   NOTES="What changed" scripts/publish-test-build.sh
#
# The app finds the server through API_DISCOVERY_URL (a gist that scripts/serve-public.ps1 keeps
# up to date), so a build works on any network. API_BASE_URL is only the first address it tries;
# by default the one in the gist right now.
#
# Bump `version:` in app/pubspec.yaml first: the number after "+" must grow.
set -euo pipefail

API_DISCOVERY_URL=${API_DISCOVERY_URL:-https://gist.githubusercontent.com/Ashfaq1306/73f5cd0421af834e9965f8680d2ea2b1/raw/study-assistant-endpoint.json}
if [ -z "${API_BASE_URL:-}" ]; then
  API_BASE_URL=$(curl -fsS "$API_DISCOVERY_URL?t=$(date +%s)" | sed -nE 's/.*"apiBaseUrl":"([^"]+)".*/\1/p')
fi
: "${API_BASE_URL:?Could not read the API address from $API_DISCOVERY_URL; set API_BASE_URL}"
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
flutter build apk --profile --split-per-abi --dart-define=API_BASE_URL="$API_BASE_URL" --dart-define=API_DISCOVERY_URL="$API_DISCOVERY_URL"
apks=()
for abi in arm64-v8a armeabi-v7a x86_64; do
  out="build/study-mate-${version}-b${build}-${abi}.apk"
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
