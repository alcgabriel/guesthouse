#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds the QEMU the Mac host runs. It fetches QEMU at one commit from QEMU's own git, checks the
# commit and its tree against the hashes below, puts the patches in patches/ on it in order, and
# builds only what the Mac host needs: qemu-system-aarch64 on Hypervisor.framework, and the arm64
# firmware. It writes two folders into the output folder:
#
#   helpers/   qemu-system-aarch64, with the pvg-fwd device, and lib/, the libraries it links that
#              macOS doesn't have, found by @loader_path. Programs only, so this is the folder
#              mac/nightly.sh takes as its helpers (--helpers), with mac/build-pvg-host.sh's
#              graphics process beside QEMU.
#   qemu/      the firmware (edk2-aarch64-code.fd and edk2-aarch64-vars.fd), QEMU's licences, the
#              firmware's, and SOURCE.txt, which says what was built from where. These are files,
#              not programs, and codesign refuses an app with files in Contents/Helpers, so they
#              are kept apart for Contents/Resources.
#
#   sh qemu/mac/build.sh [--out FOLDER] [--work FOLDER] [--configure-only]
#
# The output goes to target/mac-helpers and the work to target/qemu-mac unless told otherwise. It
# needs the Xcode command line tools, Python 3, ninja and pkg-config, and glib and pixman where
# pkg-config finds them; on a GitHub-hosted Mac, `brew install glib pixman ninja pkgconf`. libslirp,
# for the machines' network, is pkg-config's if there is one, and otherwise QEMU's own subproject,
# which QEMU's build fetches at the commit QEMU pins. QEMU_SLIRP=disabled builds without a network.
# The work folder takes about 700 MB.
set -eu

# QEMU's master on 2026-11-24, which the patches were made and tried on.
QEMU_URL=https://gitlab.com/qemu-project/qemu.git
QEMU_COMMIT=6bf90d4fc5027567cb704d7888f5ec792b4ed75a
QEMU_TREE=eae25a2711be4d920f98d7ff5269e2a355fe88e3

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out=$repo/target/mac-helpers
work=$repo/target/qemu-mac
configure_only=no
while [ $# -gt 0 ]; do
    case $1 in
        --out) out=${2:?--out wants a folder}; shift 2 ;;
        --work) work=${2:?--work wants a folder}; shift 2 ;;
        --configure-only) configure_only=yes; shift ;;
        -h | --help) sed -n 3,24p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "build.sh: unknown argument $1" >&2; exit 2 ;;
    esac
done
[ "$(uname -s)" = Darwin ] || { echo "build.sh: QEMU for the Mac host builds on a Mac" >&2; exit 1; }
for tool in git python3 ninja pkg-config xcrun; do
    command -v "$tool" >/dev/null || { echo "build.sh: $tool is missing" >&2; exit 1; }
done
for library in glib-2.0 pixman-1; do
    pkg-config --exists "$library" || { echo "build.sh: pkg-config finds no $library" >&2; exit 1; }
done
mkdir -p "$work"
work=$(cd "$work" && pwd)
src=$work/qemu
build=$work/build

# A patch's subject, with the lines it was wrapped onto put back together.
subject() {
    awk '/^Subject: / { s = substr($0, 10); on = 1; next } on && /^ / { s = s $0; next } on { print s; exit }' "$1"
}

# --- Fetch and check ---------------------------------------------------------------------------
# Only the one commit is fetched. A commit's hash covers its tree and every file in it, so the two
# checks below do what a checksum on a tarball would.
if [ ! -d "$src/.git" ]; then
    git init -q "$src"
fi
if [ "$(git -C "$src" rev-parse -q --verify "$QEMU_COMMIT^{commit}" 2>/dev/null)" != "$QEMU_COMMIT" ]; then
    echo "fetching QEMU $QEMU_COMMIT from $QEMU_URL"
    git -C "$src" fetch -q --depth 1 "$QEMU_URL" "$QEMU_COMMIT"
fi
# A tree left by an earlier run goes back to the commit as fetched. It is this script's own folder.
git -C "$src" checkout -q -f --detach "$QEMU_COMMIT"
git -C "$src" clean -q -fdx
[ "$(git -C "$src" rev-parse HEAD)" = "$QEMU_COMMIT" ] || { echo "build.sh: not the commit asked for" >&2; exit 1; }
[ "$(git -C "$src" rev-parse 'HEAD^{tree}')" = "$QEMU_TREE" ] || { echo "build.sh: QEMU's tree is not the one expected" >&2; exit 1; }
echo "QEMU $(cat "$src/VERSION") at $QEMU_COMMIT, checked"

# --- Patch -------------------------------------------------------------------------------------
for patch in "$here"/patches/*.patch; do
    echo "applying $(basename "$patch"): $(subject "$patch")"
    git -C "$src" apply --whitespace=nowarn "$patch"
done

# --- Configure ---------------------------------------------------------------------------------
# Nothing that isn't asked for: no default features, so a library that happens to be on the
# building Mac doesn't end up linked into the copy that ships. What is asked for is what the app's
# machines use: Hypervisor.framework, the framework's own device (apple-gfx-pci), the network, and
# the device tree built in. pvg-fwd is a plain PCI device and needs nothing.
if [ "${QEMU_SLIRP:-enabled}" = disabled ]; then slirp=--disable-slirp; else slirp=--enable-slirp; fi
mkdir -p "$build"
(
    cd "$build"
    "$src/configure" --target-list=aarch64-softmmu --without-default-features \
        --enable-hvf --enable-pvg --enable-fdt=internal "$slirp" \
        --disable-docs --disable-werror --disable-rust --disable-guest-agent --disable-tools \
        --extra-cflags=-mmacosx-version-min=27.0 --extra-ldflags=-mmacosx-version-min=27.0
) >"$work/configure.log" 2>&1 || { tail -n 40 "$work/configure.log" >&2; exit 1; }
echo "configured, in $build:"
grep -E '^ +(HVF support|ParavirtualizedGraphics support|slirp support|fdt support) +:' "$work/configure.log" || true
[ "$configure_only" = no ] || exit 0

# --- Build -------------------------------------------------------------------------------------
ninja -C "$build" qemu-system-aarch64 pc-bios/edk2-aarch64-code.fd pc-bios/edk2-aarch64-vars.fd \
    >"$work/build.log" 2>&1 || { tail -n 40 "$work/build.log" >&2; exit 1; }
"$build/qemu-system-aarch64" -device help | grep -q '"pvg-fwd"' \
    || { echo "build.sh: the build has no pvg-fwd device" >&2; exit 1; }

# --- helpers/ ----------------------------------------------------------------------------------
helpers=$out/helpers
mkdir -p "$helpers/lib"
cp "$build/qemu-system-aarch64" "$helpers/"

# Every library outside macOS that QEMU needs, and those they need, goes into lib/, and each
# reference to one is pointed at that copy. A Mach-O file that is changed has to be signed again
# to run: ad hoc here, and mac/nightly.sh signs everything properly after.
is_system() { case $1 in /usr/lib/* | /System/*) return 0 ;; *) return 1 ;; esac; }
# Where a reference made from FILE (first argument) points on this Mac.
resolve() {
    case $2 in
        @loader_path/*) printf '%s\n' "$(dirname "$1")/${2#@loader_path/}" ;;
        @rpath/*)
            name=${2#@rpath/}
            for dir in "$(dirname "$1")" $(otool -l "$1" | awk '/LC_RPATH/ { r = 1 } r && /path / { print $2; r = 0 }'); do
                case $dir in @loader_path*) dir=$(dirname "$1")${dir#@loader_path} ;; esac
                if [ -f "$dir/$name" ]; then printf '%s\n' "$dir/$name"; return; fi
            done
            echo "build.sh: $2, needed by $1, was not found" >&2
            exit 1
            ;;
        *) printf '%s\n' "$2" ;;
    esac
}
# Copies what FILE needs into lib/ and points FILE at the copies. ORIGIN is where FILE came from,
# for references relative to it; PREFIX is how FILE reaches lib/.
bundle() {
    file=$1 origin=$2 prefix=$3
    otool -L "$file" | tail -n +2 | awk '{ print $1 }' | while IFS= read -r ref; do
        is_system "$ref" && continue
        real=$(resolve "$origin" "$ref")
        name=$(basename "$real")
        # A library's first line is its own name.
        [ "$name" = "$(basename "$file")" ] && continue
        if [ ! -f "$helpers/lib/$name" ]; then
            cp "$real" "$helpers/lib/$name"
            printf '%s\t%s\n' "$name" "$real" >>"$work/copied.txt"
            chmod u+w "$helpers/lib/$name"
            install_name_tool -id "@loader_path/$name" "$helpers/lib/$name" 2>/dev/null
            # In a subshell of its own, as sh has no local variables.
            (bundle "$helpers/lib/$name" "$real" "@loader_path")
        fi
        install_name_tool -change "$ref" "$prefix/$name" "$file" 2>/dev/null
    done
}
: >"$work/copied.txt"
bundle "$helpers/qemu-system-aarch64" "$build/qemu-system-aarch64" "@loader_path/lib"
for file in "$helpers"/lib/*; do
    [ -f "$file" ] && codesign --force -s - "$file" 2>/dev/null
done
# QEMU keeps the one entitlement Hypervisor.framework asks for, as QEMU's own build signs it.
codesign --force -s - --entitlements "$src/accel/hvf/entitlements.plist" "$helpers/qemu-system-aarch64" 2>/dev/null
left=$(otool -L "$helpers/qemu-system-aarch64" "$helpers"/lib/* 2>/dev/null | awk '/^\t/ { print $1 }' \
    | grep -v -e '^/usr/lib/' -e '^/System/' -e '^@loader_path/' || true)
[ -z "$left" ] || { echo "build.sh: still pointing outside the folder: $left" >&2; exit 1; }
"$helpers/qemu-system-aarch64" -device help | grep -q '"pvg-fwd"' \
    || { echo "build.sh: the copy in helpers/ doesn't run" >&2; exit 1; }

# --- qemu/ -------------------------------------------------------------------------------------
# The firmware, and what a binary copy owes its users: the licences and where the source is.
data=$out/qemu
mkdir -p "$data"
cp "$build/pc-bios/edk2-aarch64-code.fd" "$build/pc-bios/edk2-aarch64-vars.fd" "$data/"
cp "$src/COPYING" "$src/COPYING.LIB" "$src/pc-bios/edk2-licenses.txt" "$data/"
# Each library's licence, from the package it was installed with: Homebrew keeps COPYING and the
# like at the top of each package's folder, two above the library.
mkdir -p "$data/licences"
while IFS="$(printf '\t')" read -r name real; do
    package=$(dirname "$(dirname "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$real")")")
    for notice in "$package"/COPYING* "$package"/LICENSE* "$package"/LICENCE*; do
        [ -f "$notice" ] || continue
        mkdir -p "$data/licences/$name"
        cp "$notice" "$data/licences/$name/"
    done
done <"$work/copied.txt"
{
    echo "qemu-system-aarch64 is QEMU $(cat "$src/VERSION"), built from $QEMU_URL"
    echo "at commit $QEMU_COMMIT, with these patches on it in this order:"
    for patch in "$here"/patches/*.patch; do
        echo "  $(basename "$patch"): $(subject "$patch")"
    done
    echo "The patches and the script that built it are in qemu/mac/ of Guesthouse's source."
    echo "edk2-aarch64-code.fd and edk2-aarch64-vars.fd are QEMU's edk2 firmware from that tree,"
    echo "under the licences in edk2-licenses.txt."
    echo "QEMU was built against these libraries, as pkg-config found them:"
    for library in glib-2.0 pixman-1 slirp; do
        if pkg-config --exists "$library"; then echo "  $library $(pkg-config --modversion "$library")"; fi
    done
    if [ "$slirp" = --enable-slirp ] && ! pkg-config --exists slirp; then
        echo "  libslirp, QEMU's subproject at the commit QEMU's subprojects/slirp.wrap names, linked in"
    fi
    echo "These came with it in lib/ beside it, unchanged but for the names they load each other by,"
    echo "with their licences in licences/ where the package that installed them had one:"
    while IFS="$(printf '\t')" read -r name real; do
        if [ -d "$data/licences/$name" ]; then
            echo "  $name"
        else
            echo "  $name (no licence file was beside it; its own project has it)"
        fi
    done <"$work/copied.txt"
} >"$data/SOURCE.txt"
echo "done: $helpers and $data"
