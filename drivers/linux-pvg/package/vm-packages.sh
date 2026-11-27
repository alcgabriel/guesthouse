#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The build VM's packages, run in it as root (vm.sh ssh sudo sh -s < vm-packages.sh).
# What a build of the module, of our Mesa and of the .deb files needs. LLVM 21
# (Ubuntu 26.04's own), clang, libclc and the SPIR-V translator only for
# mesa_clc, a tool of the build; the Mesa that is packaged links no LLVM.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get -q update
apt-get -q -y install --no-install-recommends \
	build-essential dkms debhelper fakeroot dpkg-dev git rsync file \
	linux-headers-"$(uname -r)" \
	meson ninja-build pkg-config cmake bison flex \
	python3-mako python3-yaml python3-packaging python3-ply \
	glslang-tools spirv-tools spirv-tools-dev patchelf \
	llvm-21-dev clang-21 libclang-21-dev libclang-cpp21-dev libclc-21-dev libllvmspirvlib-21-dev \
	libdrm-dev libexpat1-dev zlib1g-dev libzstd-dev libelf-dev libudev-dev \
	libwayland-dev wayland-protocols libwayland-egl-backend-dev libglvnd-dev libvulkan-dev \
	libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev libxcb1-dev libxcb-dri3-dev \
	libxcb-present-dev libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev \
	libxcb-glx0-dev libxshmfence-dev libxxf86vm-dev libxrandr-dev
echo "vm-packages: done, $(dpkg -l | grep -c '^ii') packages"
