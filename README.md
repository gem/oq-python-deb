# oq-python-deb
Python Linux packages for OpenQuake, currently supporting Ubuntu

## ubuntu

Based on https://packages.ubuntu.com/source/bionic/python3.6
Provides Python 3.6 in `/opt/openquake`


To recompile the code:

  * download `python3.6_3.6.5-3.debian.tar.xz` `python3.6_3.6.5-3.dsc` `python3.6_3.6.5.orig.tar.gz` from ubuntu archive
  * dpkg-source -x python3.6_3.6.5-3.dsc
  * rename directory `python3.6-3.6.5` to `oq-python3.6-3.6.5`
  * rename file `python3.6_3.6.5.orig.tar.gz` to `oq-python3.6_3.6.5.orig.tar.gz`
  * `cd oq-python3.6-3.6.5`
  * remove all patches with  
  `quilt pop -a`  
  command
  * rename `debian` folder to `../debian.orig`
  * clone `oq-python-deb` repository to debian folder with command  
`git clone https://github.com/gem/oq-python-deb.git debian`
  * update `debian/changelog` file accordingly with version and Ubuntu serie
  * apply all new patches with:  
`quilt push -a`
  * set GEM_DEBIAN_INSTALL_LAYOUT to `deb`  
  `export GEM_DEBIAN_INSTALL_LAYOUT=deb`
  * run  
  `dpkg-buildpackage -rfakeroot -d -T clean`  
  to generate `control` file starting from `control.in`; if something goes wrong you can also use `fakeroot ./debian/rules clean` as fallback
  * run  
  `sudo mk-build-deps --install debian/control`  
  to install build dependencies
  * if you want to build binaries quickly use:  
`export DEB_BUILD_OPTIONS="noopt notest nocheck nobench parallel=16" ; dpkg-buildpackage -rfakeroot -us -uc`
  * if you want to build binaries use:  
`export DEB_BUILD_OPTIONS="parallel=16" ; dpkg-buildpackage -rfakeroot -us -uc`
  * if you want to build sources to be uploaded:  
`export DEB_BUILD_OPTIONS="parallel=16" ; dpkg-buildpackage -S -sa`
  * if you want to change something in the original package scope create new patch and manage it with quilt (keep track of the patches changes with git)
