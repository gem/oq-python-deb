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

if [ -n "$GEM_SET_DEBUG" -a "$GEM_SET_DEBUG" != "false" ]; then
    export PS4='+${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
    set -x
fi

PKG_DIR=oq-python3.8-3.8.5

action="$1"

if [ "$action" = "buildfromsrc" ]; then
    set -e
    sudo apt-get -y --force-yes install git curl build-essential dpatch fakeroot devscripts equivs lintian quilt lsb-release
    sudo apt-get install dpkg-dev
    sudo apt-get install equivs
    sudo apt-get install build-essential pbuilder

    dpkg-source -x "$PKG_DSC"
    cd "$GEM_DEB_PACKAGE"
    mk-build-deps debian/control --install --root-cmd sudo --remove
    debuild -i -b
    # here the code

    exit 0
fi

# NOTE: this is the page for python 3.6: https://packages.ubuntu.com/source/bionic/python3.6
#
# original url: BASE_URL="https://launchpad.net/debian/+archive/primary/+files"
BASE_URL="https://ftp.openquake.org/ubuntu-src"
BUILD_UBUVER_REFERENCE="bionic"

sudo apt-get -y --force-yes install git curl build-essential dpatch fakeroot devscripts equivs lintian quilt lsb-release

# for f in python3.6_3.6.5-3.debian.tar.xz python3.6_3.6.5-3.dsc python3.6_3.6.5.orig.tar.xz; do
for f in python3.8_3.8.5.orig.tar.gz; do
    if [ -f "$f" ]; then
        continue
    fi
    curl -o "$f" -L "${BASE_URL}/${f}"
done

tar -xvf python3.8_3.8.5.orig.tar.gz -C "$PKG_DIR" --strip-components=1
cp python3.8_3.8.5.orig.tar.gz oq-python3.8_3.8.5.orig.tar.gz

cd "$PKG_DIR"

UBUNTU_SERIE="$(lsb_release -s -c)"
if [ -d debian.${UBUNTU_SERIE} ]; then
    cp -r debian.${UBUNTU_SERIE}/* debian/
fi
rm -rf debian.*

sed -i "/^${GEM_DEB_PACKAGE}.*/s/${BUILD_UBUVER_REFERENCE}/${UBUNTU_SERIE}/g" debian/changelog

export GEM_DEBIAN_INSTALL_LAYOUT=deb
fakeroot ./debian/rules clean
dpkg-buildpackage -rfakeroot -d -T clean
sudo mk-build-deps --install --remove --tool 'apt-get -y'

if [ "$DEB_BUILD_OPTIONS" == "" ]; then
    if [ "$GEM_PARALLEL" == "" ]; then
        export GEM_PARALLEL=2
    fi
    export DEB_BUILD_OPTIONS="noopt notest nocheck nobench parallel=${GEM_PARALLEL}" ;
fi

# version info from debian/changelog
h="$(grep "^$GEM_DEB_PACKAGE" debian/changelog | head -n 1)"

# is it the first item of changelog ?
h_first="$(cat debian/changelog | head -n 1)"
h_is_first=0
if [ "$h" = "$h_first" ]; then
    h_is_first=1
fi

# reading version from: Include/patchlevel.h:#define PY_VERSION      	"3.6.5"
ini_vers="$(grep '^#define PY_VERSION\b' Include/patchlevel.h | sed 's/^[^"]*"//g;s/".*//g')"
ini_maj="$(echo "$ini_vers" | sed -n 's/^\([0-9]\+\).*/\1/gp')"
ini_min="$(echo "$ini_vers" | sed -n 's/^[0-9]\+\.\([0-9]\+\).*/\1/gp')"
ini_bfx="$(echo "$ini_vers" | sed -n 's/^[0-9]\+\.[0-9]\+\.\([0-9]\+\).*/\1/gp')"

pkg_name="$(echo "$h" | cut -d ' ' -f 1)"
pkg_vers="$(echo "$h" | cut -d ' ' -f 2 | cut -d '(' -f 2 | cut -d ')' -f 1)"
pkg_rest="$(echo "$h" | cut -d ' ' -f 3-)"
pkg_maj="$(echo "$pkg_vers" | sed -n 's/^\([0-9]\+\).*/\1/gp')"
pkg_min="$(echo "$pkg_vers" | sed -n 's/^[0-9]\+\.\([0-9]\+\).*/\1/gp')"
pkg_bfx="$(echo "$pkg_vers" | sed -n 's/^[0-9]\+\.[0-9]\+\.\([0-9]\+\).*/\1/gp')"
pkg_deb="$(echo "$pkg_vers" | sed -n 's/^[0-9]\+\.[0-9]\+\.[0-9]\+\(-[^+]\+\).*/\1/gp')"
pkg_debsfx="$(echo "$pkg_vers" | sed -n "s/^[0-9]\+\.[0-9]\+\.[0-9]\+\(-[^+]\+\).*/\1/g;s/^-[0-9]*//g;s/~${UBUNTU_SERIE}[0-9]*//gp")"
pkg_suf="$(echo "$pkg_vers" | sed -n 's/^[0-9]\+\.[0-9]\+\.[0-9]\+-[^+]\+\(+.*\)/\1/gp')"

if [ $BUILD_DEVEL -eq 1 ]; then
    hash="$(git log --pretty='format:%h' -1)"
    mv debian/changelog debian/changelog.orig

    if [ "$pkg_maj" = "$ini_maj" -a "$pkg_min" = "$ini_min" -a \
         "$pkg_bfx" = "$ini_bfx" -a "$pkg_deb" != "" ]; then
        deb_ct="$(echo "$pkg_deb" | sed 's/^-//g;s/~.*//g')"
        if [ $h_is_first -eq 1 ]; then
            pkg_deb="-$(( deb_ct ))"
        else
            pkg_deb="-$(( deb_ct + 1))"
        fi
    else
        pkg_maj="$ini_maj"
        pkg_min="$ini_min"
        pkg_bfx="$ini_bfx"
        pkg_deb="-1"
    fi

    (
      echo "$pkg_name (${pkg_maj}.${pkg_min}.${pkg_bfx}${pkg_deb}${pkg_debsfx}~${BUILD_UBUVER}01~dev${dt}+${hash}) ${BUILD_UBUVER}; urgency=low"
      echo
      echo "  [Automatic Script]"
      echo "  * Development version from $hash commit"
      echo
      cat debian/changelog.orig | sed -n "/^$GEM_DEB_PACKAGE/q;p"
      echo " -- $DEBFULLNAME <$DEBEMAIL>  $(date -d@"$dt" -R)"
      echo
    )  > debian/changelog
    cat debian/changelog.orig | sed -n "/^$GEM_DEB_PACKAGE/,\$ p" >> debian/changelog
    rm debian/changelog.orig

#    sed -i "s/^__version__[  ]*=.*/__version__ = '${pkg_maj}.${pkg_min}.${pkg_bfx}${pkg_deb}~dev${dt}-${hash}'/g" openquake/baselib/__init__.py
else
    cp debian/changelog debian/changelog.orig
    cat debian/changelog.orig | sed "1 s/${UBUNTU_SERIE}/${BUILD_UBUVER}/g" > debian/changelog
    rm debian/changelog.orig
fi

if [ "$BUILD_SOURCES_COPY" == "1" ]; then
    dpkg-buildpackage -S -sa $UNSIGN_ARGS
else
    dpkg-buildpackage -rfakeroot $UNSIGN_ARGS
fi

