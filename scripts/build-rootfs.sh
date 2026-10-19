#!/bin/bash
# Builds Yugen's Linux image for phones: Arch Linux ARM with every package up to date and the tools
# the agents need (the base list in app/src/main/assets/setup.json) already installed, so first-run
# setup downloads one file and installs an agent without a system upgrade.
#
#   scripts/build-rootfs.sh [OUT_DIR]      default dist/rootfs
#
# It starts from Termux's proot build of Arch Linux ARM, runs pacman inside it with bubblewrap, and
# needs qemu-user-static with binfmt for aarch64 on an x86_64 machine. The keyring it creates to check
# the packages is deleted again, so each phone creates its own. It writes
# yugen-arch-aarch64-<date>.tar.xz with the folder yugen-arch-aarch64/ at the top, and the file's
# SHA-256 beside it; setup.json then names the release URL, the size and the hash.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-dist/rootfs}
BASE_URL=https://github.com/termux/proot-distro/releases/download/v4.34.2/archlinux-aarch64-pd-v4.34.2.tar.xz
BASE_SHA=dabc2382ddcb725969cf7b9e2f3b102ec862ea6e0294198a30c71e9a4b837f81
NAME=yugen-arch-aarch64
WORK=$(mktemp -d "${TMPDIR:-/tmp}/yugen-rootfs.XXXXXX")
# Some of the system's folders do not let even their owner in, so they are opened before removal.
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$OUT" build/rootfs

command -v bwrap >/dev/null || { echo "bubblewrap (bwrap) is needed"; exit 1; }
[ "$(uname -m)" = aarch64 ] || grep -q enabled /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null \
  || { echo "this machine cannot run aarch64 programs: install qemu-user-static"; exit 1; }

# The starting image, downloaded once and checked.
SRC=build/rootfs/$(basename "$BASE_URL")
[ -f "$SRC" ] || curl -fL -o "$SRC" "$BASE_URL"
echo "$BASE_SHA  $SRC" | sha256sum -c --quiet

ROOT=$WORK/$NAME
mkdir -p "$ROOT"
tar -xJf "$SRC" -C "$ROOT" --strip-components=1
rm -rf "$ROOT/etc/pacman.d/gnupg"
python3 -I -c "import json; m=json.load(open('app/src/main/assets/setup.json'))['rootfs']['arm64-v8a']['mirrors']; print(''.join('Server = %s\n' % s for s in m), end='')" > "$ROOT/etc/pacman.d/mirrorlist"
rm -f "$ROOT/etc/resolv.conf"; printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$ROOT/etc/resolv.conf"
# The same pacman.conf changes Yugen makes on the phone, where proot has no mount table or sandbox.
sed -i -e 's/^CheckSpace/#CheckSpace/' -e 's/^DownloadUser/#DownloadUser/' \
       -e 's/^#DisableSandboxFilesystem/DisableSandboxFilesystem/' -e 's/^#DisableSandboxSyscalls/DisableSandboxSyscalls/' "$ROOT/etc/pacman.conf"

# The base script from setup.json, then the caches and the keyring go.
python3 -I -c "import json; print(json.load(open('app/src/main/assets/setup.json'))['base'])" > "$WORK/base.sh"
cat >> "$WORK/base.sh" <<'EOF'
rm -rf /var/cache/pacman/pkg/* /root/.cache /root/.npm /etc/pacman.d/gnupg
rm -rf /usr/share/man/* /usr/share/doc/* /usr/share/info/* /usr/share/gtk-doc/*
EOF
bwrap --unshare-user --uid 0 --gid 0 --bind "$ROOT" / --dev /dev --proc /proc --tmpfs /tmp \
  --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin --setenv HOME /root --setenv LANG C.UTF-8 \
  --ro-bind "$WORK/base.sh" /base.sh /bin/bash /base.sh > "$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log"; echo "the base script failed"; exit 1; }
# The sandbox's mount points for the script are not part of the system.
# The system's top folder is read-only (555), so it opens for the removal and closes again.
chmod u+w "$ROOT"; rm -f "$ROOT/base.sh"; chmod u-w "$ROOT"
for t in node npm git python3 rg jq curl; do
  bwrap --unshare-user --uid 0 --gid 0 --bind "$ROOT" / --dev /dev --proc /proc --setenv PATH /usr/bin /bin/sh -c "command -v $t >/dev/null" \
    || { echo "$t is missing from the image"; exit 1; }
done

STAMP=$(date -u +%Y%m%d)
FILE=$OUT/$NAME-$STAMP.tar.xz
# Owned by root inside the archive, as a system image is, with the dates and modes pacman left; the
# packer reads files such as dbus-daemon-launch-helper that this user may not read (see its header).
python3 -I scripts/pack-rootfs.py "$WORK" "$NAME" | xz -T0 -6 > "$FILE.part"
mv "$FILE.part" "$FILE"
(cd "$OUT" && sha256sum "$(basename "$FILE")" > "$(basename "$FILE").sha256")
echo "$FILE: $(du -m "$FILE" | cut -f1) MB, unpacked $(du -sm "$ROOT" 2>/dev/null | cut -f1) MB"
cat "$FILE.sha256"
grep -E "^Packages \(|Total (Download|Installed) Size" "$WORK/build.log" | cut -c1-80
