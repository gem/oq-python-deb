# oq-python-deb
Python Linux packages for OpenQuake, currently supporting Ubuntu

## ubuntu

Based on https://packages.ubuntu.com/zesty/python3.5
Provides Python 3.5 in `/opt/openquake`


To recompile the code:

  * download python3.5_3.5.3-1ubuntu0~17.04.2.debian.tar.xz, python3.5_3.5.3-1ubuntu0_17.04.2.dsc and python3.5_3.5.3.orig.tar.xz from ubuntu archive
  * dpkg-source -x python3.5_3.5.3-1ubuntu0_17.04.2.dsc
  * rename directory python3.5-3.5.3 to oq-python3.5-3.5.3
  * cd oq-python3.5-3.5.3
  * remove all patches with `quilt pop -a` command
  * rename `debian` folder to `debian.orig`
  * clone `oq-python-deb` repository to debian folder with command
    `git clone https://github.com/gem/oq-python-deb.git debian`
  * apply all new patches with `quilt push -a` command
  * if you want to build binaries quickly use:
    `export DEB_BUILD_OPTIONS="noopt notest nocheck nobench parallel=16" ; dpkg-buildpackage -rfakeroot -us -uc`
  * if you want to build binaries use:
    `export DEB_BUILD_OPTIONS="parallel=16" ; dpkg-buildpackage -rfakeroot -us -uc`
  * if you want to build sources to be uploaded:
    `export DEB_BUILD_OPTIONS="parallel=16" ; dpkg-buildpackage -S -sa`
  * if you want to change something in the original package scope create new patch and manage it
    with quilt (keep track of the patches changes with git)
