#!/bin/bash

PKG_DIR=oq-python3.5-3.5.4
echo "TODO: download the 3 file used by dpkg-source"

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
