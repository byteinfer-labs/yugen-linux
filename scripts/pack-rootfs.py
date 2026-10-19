#!/usr/bin/env python3
"""Writes a root filesystem folder as a tar stream on stdout, as root would see it.

    scripts/pack-rootfs.py PARENT NAME | xz > image.tar.xz

PARENT/NAME is a system built by an ordinary user (scripts/build-rootfs.sh), so some of its files
and folders are not readable by that user, such as dbus-daemon-launch-helper (4750). Each one keeps
its mode in the archive: the walk notes the mode, gives the owner read access (and entry to a
folder) so it can read it, and writes the noted mode. Every entry is owned by root (0:0), and dates
are kept, because pacman compares the package lists' dates with the mirror's.
"""
import os
import stat
import sys
import tarfile

parent, name = sys.argv[1], sys.argv[2]
top = os.path.join(parent, name)
out = tarfile.open(fileobj=sys.stdout.buffer, mode="w|", format=tarfile.GNU_FORMAT)


def info(path, arc, st):
    """The archive entry for path with its true mode, owned by root."""
    t = out.gettarinfo(path, arc)
    t.mode = stat.S_IMODE(st.st_mode)
    t.uid = t.gid = 0
    t.uname = t.gname = "root"
    t.mtime = st.st_mtime
    return t


def add(path, arc):
    st = os.lstat(path)
    if stat.S_ISDIR(st.st_mode):
        if st.st_mode & 0o500 != 0o500:
            os.chmod(path, st.st_mode | 0o700)
        out.addfile(info(path, arc, st))
        for child in sorted(os.listdir(path)):
            add(os.path.join(path, child), arc + "/" + child)
    elif stat.S_ISREG(st.st_mode):
        if not st.st_mode & stat.S_IRUSR:
            os.chmod(path, st.st_mode | stat.S_IRUSR)
        with open(path, "rb") as f:
            out.addfile(info(path, arc, st), f)
    else:
        # Links, devices and fifos carry no data to read.
        out.addfile(info(path, arc, st))


add(top, name)
out.close()
