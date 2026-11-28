#!/bin/sh
# Builds the Rust core for macOS on Apple silicon and wraps it as an XCFramework that Swift
# imports as `GuesthouseCore`. Run from anywhere; the output is build/GuesthouseCore.xcframework.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
export PATH="$HOME/.cargo/bin:$PATH"
# The same minimum as the app, so the linker has nothing to warn about.
export MACOSX_DEPLOYMENT_TARGET=27.0
target=aarch64-apple-darwin

out=build/GuesthouseCore.xcframework
headers=build/core-headers
rm -rf "$out" "$headers"
mkdir -p "$headers"
cp core/include/guesthouse_core.h "$headers/"
cat > "$headers/module.modulemap" <<EOF
module GuesthouseCore {
    header "guesthouse_core.h"
    export *
}
EOF

cargo build --release --manifest-path core/Cargo.toml --target "$target"
xcodebuild -create-xcframework \
    -library "core/target/$target/release/libguesthouse_core.a" -headers "$headers" \
    -output "$out"
