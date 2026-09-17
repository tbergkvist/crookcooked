#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}/.."
app_dir="$project_dir/dist/Crookcooked.app"
contents_dir="$app_dir/Contents"
executable_dir="$contents_dir/MacOS"
bundle_identifier="${BUNDLE_IDENTIFIER:-app.crookcooked.mac.local}"
code_sign_identity="${CODE_SIGN_IDENTITY:--}"
version="${VERSION:-0.1.0}"
universal_build="${UNIVERSAL_BUILD:-0}"

cd "$project_dir"
if [[ "$universal_build" == "1" ]]; then
  arm_build="$project_dir/.build/release-arm64"
  intel_build="$project_dir/.build/release-x86_64"
  swift build -c release --product CrookcookedMac --triple arm64-apple-macosx14.0 --build-path "$arm_build"
  swift build -c release --product CrookcookedMac --triple x86_64-apple-macosx14.0 --build-path "$intel_build"
  binary_sources=(
    "$arm_build/arm64-apple-macosx/release/CrookcookedMac"
    "$intel_build/x86_64-apple-macosx/release/CrookcookedMac"
  )
else
  swift build -c release --product CrookcookedMac
  binary_sources=("$project_dir/.build/release/CrookcookedMac")
fi

/bin/rm -rf "$app_dir"
/bin/mkdir -p "$executable_dir" "$contents_dir/Resources"
if [[ "$universal_build" == "1" ]]; then
  /usr/bin/lipo -create "${binary_sources[@]}" -output "$executable_dir/CrookcookedMac"
else
  /bin/cp "${binary_sources[1]}" "$executable_dir/CrookcookedMac"
fi
/bin/cp "Config/MacInfo.plist" "$contents_dir/Info.plist"
/bin/cp "Config/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_dir/Info.plist"
/usr/bin/codesign \
  --force \
  --options runtime \
  --entitlements "$project_dir/Config/CrookcookedMac.entitlements" \
  --sign "$code_sign_identity" \
  --identifier "$bundle_identifier" \
  "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"

echo "Built $app_dir"
echo "Architectures: $(/usr/bin/lipo -archs "$executable_dir/CrookcookedMac")"
echo "Signing identity: $code_sign_identity"
