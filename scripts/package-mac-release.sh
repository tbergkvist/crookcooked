#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}/.."
archive="$project_dir/dist/crookcooked-mac.zip"
checksum="$archive.sha256"
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-}"

UNIVERSAL_BUILD=1 "$project_dir/scripts/build-mac-app.sh"
/bin/rm -f "$archive" "$checksum"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$project_dir/dist/crookcooked.app" "$archive"

if [[ -n "$notary_profile" ]]; then
  /usr/bin/xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
  /usr/bin/xcrun stapler staple "$project_dir/dist/crookcooked.app"
  /bin/rm -f "$archive"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$project_dir/dist/crookcooked.app" "$archive"
fi

(cd "$project_dir/dist" && /usr/bin/shasum -a 256 "${archive:t}" > "${checksum:t}")

if [[ "${COPY_TO_WEBSITE:-0}" == "1" ]]; then
  /bin/mkdir -p "$project_dir/website/downloads"
  /bin/cp "$archive" "$checksum" "$project_dir/website/downloads/"
fi

echo "Packaged $archive"
echo "Checksum: $checksum"
