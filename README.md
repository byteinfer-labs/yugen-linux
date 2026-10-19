# Yugen Linux

This repository publishes the Linux system that Yugen and Yugen Plus download on a phone. Each
release holds one image, `yugen-arch-aarch64-<date>.tar.xz`, and its SHA-256, and the app checks the
file against the hash written into its setup manifest before it unpacks it.

The image is Arch Linux ARM with every package updated on the release date. Node.js, npm, git,
Python, ripgrep, jq and curl are already installed, so the app installs a coding agent with a single
npm command and no system upgrade. The image holds no package cache and no pacman keyring, and each
phone creates its own keyring the first time it installs a package.

The build starts from the Arch Linux ARM image that Termux publishes for proot
(`archlinux-aarch64-pd-v4.34.2.tar.xz`), runs pacman inside it with bubblewrap, and writes the archive
with `scripts/pack-rootfs.py`, which records every file as owned by root with its original mode and
date. `scripts/build-rootfs.sh` runs from the Yugen app's source tree, because it reads the package
list from the app's setup manifest, and it needs qemu-user-static on an x86_64 machine.

Arch Linux ARM and its packages are the work of their authors and keep their own licences.
