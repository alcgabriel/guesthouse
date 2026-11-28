#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
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

# The lab's own build places (core/src/lab.rs) are compiled in only inside the lab's tree, which
# has the driver's scripts beside the app; a public checkout has none of them.
features=""
if [ -f "$here/../scripts/mac/run.sh" ]; then features="--features lab"; fi

# shellcheck disable=SC2086
# The remote-view crate's sentences, as data, from the pinned crate: the app and its tests read them.
manifest=core/Cargo.toml
cargo metadata --format-version 1 --manifest-path "$manifest" \
    | python3 -c 'import json,sys,os; m=json.load(sys.stdin); p=[x for x in m["packages"] if x["name"]=="guesthouse-remote-view-core"][0]; print(os.path.join(os.path.dirname(p["manifest_path"]),"wording.json"))' \
    > build/wording.path
cp "$(cat build/wording.path)" build/wording.json
rm build/wording.path

cargo build --release --manifest-path core/Cargo.toml --target "$target" $features
xcodebuild -create-xcframework \
    -library "core/target/$target/release/libguesthouse_core.a" -headers "$headers" \
    -output "$out"
