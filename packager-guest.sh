#!/bin/bash
#
# packager-guest.sh  Copyright (C) 2018 GEM Foundation
#
# OpenQuake is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# OpenQuake is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with OpenQuake.  If not, see <http://www.gnu.org/licenses/>.

# page for python 3.6: https://packages.ubuntu.com/source/bionic/python3.6

if [ -n "$GEM_SET_DEBUG" -a "$GEM_SET_DEBUG" != "false" ]; then
    export PS4='+${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
    set -x
fi

PKG_DIR=oq-python3.5-3.5.4

BASE_URL="https://launchpad.net/debian/+archive/primary/+files"

sudo apt-get -y --force-yes install curl build-essential dpatch fakeroot devscripts equivs lintian quilt lsb-release

for f in python3.5_3.5.4-4.dsc python3.5_3.5.4.orig.tar.gz python3.5_3.5.4-4.debian.tar.xz; do
    if [ -f "$f" ]; then
        continue
    fi
    curl -o "$f" -L "${BASE_URL}/${f}"
done

tar -xvf python3.5_3.5.4.orig.tar.gz -C "$PKG_DIR" --strip-components=1
cp python3.5_3.5.4.orig.tar.gz oq-python3.5_3.5.4.orig.tar.gz

cd "$PKG_DIR"

# FIXME: remove exit
# env
# exit 0

UBUNTU_SERIE="$(lsb_release -s -c)"
sed -i "1 s/xenial/${UBUNTU_SERIE}/g" debian/changelog

export GEM_DEBIAN_INSTALL_LAYOUT=deb
dpkg-buildpackage -rfakeroot -d -T clean
sudo mk-build-deps --install --remove --tool 'apt-get -y'

if [ "$DEB_BUILD_OPTIONS" == "" ]; then
    if [ "$GEM_PARALLEL" == "" ]; then
        export GEM_PARALLEL=2
    fi
    export DEB_BUILD_OPTIONS="noopt notest nocheck nobench parallel=${GEM_PARALLEL}" ;
fi

if [ "$BUILD_SOURCES_COPY" == "1" ]; then
    dpkg-buildpackage -S -sa $UNSIGN_ARGS
else
    dpkg-buildpackage -rfakeroot $UNSIGN_ARGS
fi

