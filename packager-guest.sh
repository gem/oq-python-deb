#!/bin/bash

# page for python 3.6: https://packages.ubuntu.com/source/bionic/python3.6

PKG_DIR=oq-python3.5-3.5.4

BASE_URL="https://launchpad.net/debian/+archive/primary/+files"

for f in python3.5_3.5.4-4.dsc python3.5_3.5.4.orig.tar.gz python3.5_3.5.4-4.debian.tar.xz; do
    if [ -f "$f" ]; then
        continue
    fi
    curl -o "$f" -L "${BASE_URL}/${f}"
done

if [ -d origin ]; then
    rm -rf origin
fi
mkdir origin
dpkg-source -x python3.5_3.5.4-4.dsc origin/python3.5-3.5.4
cd origin/python3.5-3.5.4
quilt pop -a
cd -
mv origin/python3.5-3.5.4/debian origin/debian.orig
cp python3.5_3.5.4.orig.tar.gz oq-python3.5_3.5.4.orig.tar.gz
cp -a origin/python3.5-3.5.4/* "$PKG_DIR/"

cd "$PKG_DIR"
export GEM_DEBIAN_INSTALL_LAYOUT=deb
dpkg-buildpackage -rfakeroot -d -T clean
export DEB_BUILD_OPTIONS="noopt notest nocheck nobench parallel=16" ; dpkg-buildpackage -rfakeroot -us -uc
