#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="$(xcode-select -p)"

cd "$ROOT_DIR"
BIN_DIR="$(swift build --show-bin-path)"

# Do not expose a previously staged framework while compiling: Swift must load
# its macro plug-ins from the active toolchain.
rm -rf "$BIN_DIR/PackageFrameworks/Testing.framework"
rm -f "$BIN_DIR/lib_TestingInterop.dylib"

# Some standalone Command Line Tools installations ship Swift Testing outside
# the runtime search path. Stage those files beside the test bundle when needed.
TESTING_FRAMEWORK="$DEVELOPER_DIR/Library/Developer/Frameworks/Testing.framework"
TESTING_INTEROP="$DEVELOPER_DIR/Library/Developer/usr/lib/lib_TestingInterop.dylib"
TESTING_MACROS="$DEVELOPER_DIR/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

SWIFT_BUILD_ARGS=(--build-tests)
if [[ -f "$TESTING_MACROS" ]]; then
    SWIFT_BUILD_ARGS+=(
        -Xswiftc -load-plugin-library
        -Xswiftc "$TESTING_MACROS"
    )
fi

swift build "${SWIFT_BUILD_ARGS[@]}"
if [[ -d "$TESTING_FRAMEWORK" ]]; then
    mkdir -p "$BIN_DIR/PackageFrameworks"
    rm -rf "$BIN_DIR/PackageFrameworks/Testing.framework"
    cp -R "$TESTING_FRAMEWORK" "$BIN_DIR/PackageFrameworks/"
fi
if [[ -f "$TESTING_INTEROP" ]]; then
    cp "$TESTING_INTEROP" "$BIN_DIR/"
fi

swift test --skip-build
