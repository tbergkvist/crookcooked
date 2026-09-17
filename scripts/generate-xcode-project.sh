#!/bin/zsh
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

cd "${0:A:h}/.."
xcodegen generate
echo "Generated Crookcooked.xcodeproj"
