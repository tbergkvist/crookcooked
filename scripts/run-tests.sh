#!/bin/zsh
set -euo pipefail

# Runs the CrookcookedCore test suite.
#
# With a full Xcode toolchain, `swift test` works on its own. On a machine with
# only the Command Line Tools installed, Swift Testing is present but neither the
# framework nor its interop library is on the default search path, so add them.

cd "${0:A:h}/.."

clt_frameworks="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
clt_lib="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ "$(xcode-select -p)" == *CommandLineTools* && -d "$clt_frameworks/Testing.framework" ]]; then
  exec swift test \
    -Xswiftc -F"$clt_frameworks" \
    -Xlinker -rpath -Xlinker "$clt_frameworks" \
    -Xlinker -rpath -Xlinker "$clt_lib" \
    "$@"
fi

exec swift test "$@"
