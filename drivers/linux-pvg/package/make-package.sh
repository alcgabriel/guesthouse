#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Makes Guesthouse's Linux driver package for Ubuntu 26.04 arm64, the folder
# the Mac app takes (GUESTHOUSE_DRIVER_DIR) and puts on a disk labelled RUXN:
#   install.sh                          installs the three below (and with --gnome or
#                                       --plasma one of the last two), says how on /dev/ttyAMA0
#   pvg-dkms_V_all.deb                  the kernel driver's sources, built by DKMS
#   pvg-mesa_V_arm64.deb                our Mesa in /opt/pvg-mesa
#   guesthouse-desktop_V_all.deb        weston at boot on the pvg device
#   guesthouse-gnome_V_all.deb          Ubuntu's GNOME in place of weston
#   guesthouse-plasma_V_all.deb         KDE Plasma in place of weston
#   guesthouse-linux-driver-latest.json the manifest: every file once, with its sum
# from the commits it names: the driver (drivers/linux-pvg of this repo) and
# our Mesa (a pvg-air branch). The Mesa is built in the build VM when
# PVG_MESA_STAGE is not given (build-mesa.sh); the .deb files are made there
# too, and the DKMS package is built and installed there once as a check.
#
# Usage: make-package.sh PROJECT_ROOT OUT_DIR
# Environment:
#   PVG_VERSION      the package's version (0.1.0)
#   PVG_DRIVER       the commit of drivers/linux-pvg (HEAD)
#   PVG_MESA_TREE    a Mesa tree with our pvg-air branch (needed), PVG_MESA_COMMIT its commit (HEAD)
#   PVG_MESA_STAGE   a Mesa install from build-mesa.sh for that commit, if there is one
#                    (target/linux-pvg/mesa/stage-COMMIT is taken when it is there)
#   PVG_VM_UP        yes: the build VM runs already
set -eu
root=$(cd "$1" && pwd)
out=$2
version=${PVG_VERSION:-0.1.0}
driver=$(git -C "$root" rev-parse --short=7 "${PVG_DRIVER:-HEAD}")
mesa_tree=${PVG_MESA_TREE:?names a Mesa tree with our pvg-air branch}
mesa=$(git -C "$mesa_tree" rev-parse --short=11 "${PVG_MESA_COMMIT:-HEAD}")
mesa_branch=$(git -C "$mesa_tree" branch --show-current)
here=$root/drivers/linux-pvg/package
vm="sh $here/vm.sh $root"
stage=${PVG_MESA_STAGE:-$root/target/linux-pvg/mesa/stage-$mesa}
if [ ! -d "$stage/opt/pvg-mesa" ]; then
	PVG_OUT=$root/target/linux-pvg/mesa sh "$here/build-mesa.sh" "$root" "$mesa_tree" "$mesa"
fi
if [ "${PVG_VM_UP:-}" != yes ]; then
	$vm start 900
	trap '$vm stop' EXIT
fi
echo "make-package: version $version, driver $driver, Mesa $mesa_branch $mesa"

# What goes into the VM: the driver at its commit, the Mesa install, this
# folder at the commit of the driver's tree or as it is (it is packaging).
in=$(mktemp -d /tmp/pvg-pkg.XXXXXX)
git -C "$root" archive "$driver" drivers/linux-pvg/driver drivers/linux-pvg/uapi | tar -x -C "$in"
mv "$in/drivers/linux-pvg/driver" "$in/drivers/linux-pvg/uapi" "$in/"
rm -rf "$in/drivers"
mkdir -p "$in/stage" "$in/tools" "$in/drirc"
cp -R "$stage/opt" "$in/stage/"
cp -R "$here/dkms" "$here/mesa-pkg" "$here/desktop" "$here/gnome" "$here/plasma" "$in/tools/"
cp "$here/drirc/"*.conf "$in/drirc/"
echo "$version" > "$in/version"
echo "drivers/linux-pvg at $driver" > "$in/sources-driver"
echo "Mesa $mesa_branch at $mesa (KosmicKrisp with the pvg bridge, Zink)" > "$in/sources-mesa"
$vm ssh 'rm -rf ~/pkg-in && mkdir ~/pkg-in'
COPYFILE_DISABLE=1 tar -C "$in" -cf - . | $vm ssh 'tar -C ~/pkg-in -xf - 2>/dev/null'
rm -rf "$in"
$vm ssh sh -s < "$here/vm-debs.sh"

# A check in the build VM: the DKMS package builds and installs the module
# for the VM's kernel, which is Ubuntu 26.04's own.
$vm ssh "sudo dpkg -i ~/pkg-out/pvg-dkms_${version}_all.deb > ~/dkms-check.log 2>&1; \
	dkms status -m pvg; modinfo -F vermagic pvg; sudo dpkg -r pvg-dkms >> ~/dkms-check.log 2>&1; \
	dkms status -m pvg | grep -q . && echo 'make-package: dkms remove left something' || true"

rm -rf "$out"
mkdir -p "$out"
$vm ssh 'tar -C ~/pkg-out -cf - .' | tar -C "$out" -xf -
sed "s|@VERSION@|$version|" "$here/install.sh" > "$out/install.sh"
chmod 755 "$out/install.sh"
# The manifest, in the shape of the Windows one. Its published names carry the version.
(
	cd "$out"
	first=yes
	printf '{"version": "%s", "files": [\n' "$version"
	for f in install.sh pvg-dkms_${version}_all.deb pvg-mesa_${version}_arm64.deb guesthouse-desktop_${version}_all.deb \
		guesthouse-gnome_${version}_all.deb guesthouse-plasma_${version}_all.deb; do
		[ -f "$f" ] || { echo "make-package: $f is missing" >&2; exit 1; }
		[ $first = yes ] || printf ',\n'
		first=no
		printf '  {"name": "guesthouse-linux-driver-%s-%s", "as": "%s", "sha256": "%s"}' \
			"$version" "$f" "$f" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
	done
	printf '\n]}\n'
) > "$out/guesthouse-linux-driver-latest.json"
ls -l "$out"
cat "$out/guesthouse-linux-driver-latest.json"
