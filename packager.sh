#!/bin/bash
#
# packager.sh  Copyright (C) 2018 GEM Foundation
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
set -e
GEM_GIT_REPO="git://github.com/gem"
GEM_GIT_PACKAGE="oq-python-deb"

GEM_DEB_PACKAGE="oq-python3.5"
GEM_DEB_SERIE="master"
if [ -z "$GEM_DEB_REPO" ]; then
    GEM_DEB_REPO="$HOME/gem_ubuntu_repo"
fi
if [ -z "$GEM_DEB_MONOTONE" ]; then
    GEM_DEB_MONOTONE="$HOME/monotone"
fi

GEM_BUILD_ROOT="build-deb"
GEM_BUILD_SRC="${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}"

GEM_MAXLOOP=20

GEM_ALWAYS_YES=false

if [ "$GEM_EPHEM_CMD" = "" ]; then
    GEM_EPHEM_CMD="lxc-copy"
fi
if [ "$GEM_EPHEM_NAME" = "" ]; then
    GEM_EPHEM_NAME="ubuntu16-lxc-eph"
fi
# FIXME this is currently unused, but left as reference
if [ "$GEM_EPHEM_USER" = "" ]; then
    GEM_EPHEM_USER="ubuntu"
fi

LXC_VER=$(lxc-ls --version | cut -d '.' -f 1)

if [ "$LXC_VER" -lt 2 ]; then
    echo "LXC >= 2.0.0 is required." >&2
    echo "Hint: LXC 2.0 is available for Trusty from backports."
    exit 1
fi

if [ -z "$LXC_TERM" ]; then
    LXC_TERM="lxc-stop -t 10"
fi

if [ -z "$LXC_KILL" ]; then
    LXC_KILL="lxc-stop -k"
fi

if [ -z "$LXC_DESTROY" ]; then
    LXC_DESTROY="lxc-destroy"
fi

if [ -z "$GEM_EPHEM_EXE" ]; then
    GEM_EPHEM_EXE="${GEM_EPHEM_CMD} -n ${GEM_EPHEM_NAME} -e"
fi

NL="
"
TB="	"

OPT_LIBS_PATH=/opt/openquake/lib/python3/dist-packages:/opt/openquake/lib/python3.5/dist-packages

#
#  sig_hand - manages cleanup if the build is aborted
#
sig_hand () {
    trap ERR
    echo "signal trapped"
    if [ "$lxc_name" != "" ]; then
        set +e
        scp "${lxc_ip}:ssh.log" "out_${BUILD_UBUVER}/ssh.history"
        echo "Destroying [$lxc_name] lxc"
        sudo $LXC_KILL -n "$lxc_name"
        sudo $LXC_DESTROY -n "$lxc_name"
    fi
    if [ -f /tmp/packager.eph.$$.log ]; then
        rm /tmp/packager.eph.$$.log
    fi
    exit 1
}


#
#  repo_id_get - retry git repo from local git remote command
repo_id_get () {
    local repo_name repo_line

    if ! repo_name="$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null)"; then
        repo_line="$(git remote -vv | grep "^origin[ ${TB}]" | grep '(fetch)$')"
        if [ -z "$repo_line" ]; then
            echo "no remote repository associated with the current branch, exit 1"
            exit 1
        fi
    else
        repo_name="$(echo "$repo_name" | sed 's@/.*@@g')"

        repo_line="$(git remote -vv | grep "^${repo_name}[ ${TB}].*(fetch)\$")"
    fi

    if echo "$repo_line" | grep -q '[0-9a-z_-\.]\+@[a-z0-9_-\.]\+:'; then
        repo_id="$(echo "$repo_line" | sed "s/^[^ ${TB}]\+[ ${TB}]\+[^ ${TB}@]\+@//g;s/.git[ ${TB}]\+(fetch)$/.git/g;s@/${GEM_GIT_PACKAGE}.git@@g;s@:@/@g")"
    else
        repo_id="$(echo "$repo_line" | sed "s/^[^ ${TB}]\+[ ${TB}]\+git:\/\///g;s/.git[ ${TB}]\+(fetch)$/.git/g;s@/${GEM_GIT_PACKAGE}.git@@g")"
    fi

    echo "$repo_id"
}

#
#  _lxc_name_and_ip_get <filename> - retrieve name and ip of the runned ephemeral lxc and
#                                    put them into global vars "lxc_name" and "lxc_ip"
#      <filename>    file where lxc-start-ephemeral output is saved
#
_lxc_name_and_ip_get()
{
    local filename="$1" i e

    i=-1
    e=-1
    for i in $(seq 1 40); do
        if grep -q " as clone of $GEM_EPHEM_NAME" "$filename" 2>&1 ; then
            lxc_name="$(grep " as clone of $GEM_EPHEM_NAME" "$filename" | tail -n 1 | sed "s/Created \(.*\) as clone of ${GEM_EPHEM_NAME}/\1/g")"
            break
        else
            sleep 2
        fi
    done
    if [ "$i" -eq 40 ]; then
        return 1
    fi

    for e in $(seq 1 40); do
        sleep 2
        lxc_ip="$(sudo lxc-ls -f --filter "^${lxc_name}\$" | tail -n 1 | sed 's/ \+/ /g' | cut -d ' ' -f 5)"
        if [ "$lxc_ip" -a "$lxc_ip" != "-" ]; then
            lxc_ssh="${GEM_EPHEM_USER}@${lxc_ip}"
            break
        fi
    done
    if [ "$e" -eq 40 ]; then
        return 1
    fi
    echo "SUCCESSFULLY STARTED: $lxc_name ($lxc_ip)"

    return 0
}

#
#  _wait_ssh <lxc_ip> - wait until the new lxc ssh daemon is ready
#      <lxc_ip>    the IP address of lxc instance
#
_wait_ssh () {
    local lxc_ip="$1"

    for i in $(seq 1 20); do
        if ssh "$lxc_ip" "echo begin"; then
            break
        fi
        sleep 2
    done
    if [ "$i" -eq 20 ]; then
        return 1
    fi
}


usage () {
    ret="$1"
#       if -B is present binary package is build too.
#       if -R is present update the local repository to the new current package"
    cat <<EOF

USAGE:

    $0 [<-s|--serie> <precise|trusty|xenial>] [-D|--development] [-S|--sources_copy] build <branch>

    --serie             (def. trusty)
       if -s is present try to produce sources for a specific ubuntu version (precise, trusty or xenial),
           (default precise)
       if -S is present try to copy sources to <GEM_DEB_MONOTONE>/<BUILD_UBUVER>/source directory
       if -D is present a package with self-computed version is produced."

ENVIRONMENT:

    GEM_DEB_REPO        (def. "\$HOME/gem_ubuntu_repo")
    GEM_DEB_MONOTONE    (def. "\$HOME/monotone")
    GEM_EPHEM_CMD       (def. "lxc-copy")
    GEM_EPHEM_NAME      (def. "ubuntu16-lxc-eph")
    GEM_EPHEM_USER      (def. "ubuntu")
    LXC_TERM            (def. "lxc-stop -t 10")
    LXC_KILL            (def. "lxc-stop -k")
    LXC_DESTROY         (def. "lxc-destroy")
    GEM_EPHEM_EXE       (def. "\${GEM_EPHEM_CMD} -n \${GEM_EPHEM_NAME} -e")

EOF

    exit $ret
}


#
#  _build_innervm_run <lxc_ip> <branch>
#
#      <lxc_ip>   the IP address of lxc instance
#      <branch>   name of the tested branch
#
_build_innervm_run () {
    local lxc_ip="$1" branch="$2"
    local i old_ifs pkgs_list dep

    trap 'local LASTERR="$?" ; trap ERR ; (exit $LASTERR) ; return' ERR

    ssh "$lxc_ip" "rm -f ssh.log"

    ssh "$lxc_ip" "sudo apt-get update"
    ssh "$lxc_ip" "sudo apt-get -y upgrade"
    gpg -a --export | ssh "$lxc_ip" "sudo apt-key add -"

#    add_custom_pkg_repo

    ssh "$lxc_ip" "sudo apt-get upgrade -y"

    if [ -f _jenkins_deps_info ]; then
        source _jenkins_deps_info
    fi

    if [ -f gem_date_file ]; then
        dt="$(cat gem_date_file)"
    else
        dt="$(date +%s)"
        echo "$dt" > gem_date_file
    fi

    # install sources of this package
    cw="$(pwd)"
    cwb="$(basename "$cw")"
    cd ..
    scp -r "$cwb" "$lxc_ip:${GEM_GIT_PACKAGE}"
    cd -

    #    git archive --prefix "${GEM_GIT_PACKAGE}/" HEAD | ssh "$lxc_ip" "tar xv"

    # configure the machine to run tests
    if [ -z "$GEM_DEVTEST_SKIP_TESTS" ]; then
        echo "TODO: tests management"
    fi

    ssh "$lxc_ip" "
        set -e
        export BUILD_UBUVER=\"$BUILD_UBUVER\"
        export dt=\"$dt\"
        export DEBEMAIL=\"$DEBEMAIL\"
        export DEBFULLNAME=\"$DEBFULLNAME\"
        export GEM_SET_DEBUG=\"$GEM_SET_DEBUG\"
        export DEB_BUILD_OPTIONS=\"noopt notest nocheck nobench parallel=16\"
        export BUILD_SOURCES_COPY=\"$BUILD_SOURCES_COPY\"
        export UNSIGN_ARGS=\"$UNSIGN_ARGS\"
        export BUILD_DEVEL=\"$BUILD_DEVEL\"

        cd \"${GEM_GIT_PACKAGE}\"
        ./packager-guest.sh"

    scp "$lxc_ip:${GEM_GIT_PACKAGE}/oq-*.{tar.?z,changes,dsc}" "${GEM_BUILD_ROOT}" || true
    scp "$lxc_ip:${GEM_GIT_PACKAGE}/*.deb" "${GEM_BUILD_ROOT}" || true

    trap ERR

    return
}


#
#  build_run <branch> - main function to build on LXC machine
#      <branch>    name of the tested branch
#
build_run () {
    local branch="$1"
#    local dep dep_item dep_type old_ifs branch_cur

    if [ ! -d "out_${BUILD_UBUVER}" ]; then
        mkdir "out_${BUILD_UBUVER}"
    fi

    if [ ! -d "${GEM_BUILD_ROOT}" ]; then
        mkdir "${GEM_BUILD_ROOT}"
    fi

    if [ ! -d _jenkins_deps ]; then
        mkdir _jenkins_deps
    fi

    #
    #  dependencies repos
    #
    # in test sources different repositories and branches can be tested
    # consistently: for each openquake dependency it try to use
    # the same repository and the same branch OR the gem repository
    # and the same branch OR the gem repository and the "master" branch
    #

    sudo ${GEM_EPHEM_EXE} 2>&1 | tee /tmp/packager.eph.$$.log &
    _lxc_name_and_ip_get /tmp/packager.eph.$$.log

    _wait_ssh "$lxc_ip"
    set +e
    _build_innervm_run "$lxc_ip" "$branch"
    inner_ret=$?
    sudo $LXC_TERM -n "$lxc_name"

    if [ $inner_ret -ne 0 ]; then
        return $inner_ret
    fi

    set -e
    commit="$(git log --pretty='format:%h' -1)"

    #
    #  prepare repo and install $GEM_DEB_PACKAGE package
    cd ${GEM_BUILD_ROOT}
    dpkg-scanpackages . /dev/null >Packages
    cat Packages | gzip -9c > Packages.gz
    dpkg-scansources . > Sources
    cat Sources | gzip > Sources.gz
    cat > Release <<EOF
Origin: openquake-${BUILD_UBUVER}
Label: OpenQuake Local Ubuntu Repository
Codename: $BUILD_UBUVER
Date: $(date -R)
Architectures: amd64
Components: main
Description: OpenQuake Local Ubuntu Repository
SHA256:
EOF
    ( printf ' '"$(sha256sum Packages | cut --delimiter=' ' --fields=1)"' %16d Packages\n' \
             "$(wc --bytes Packages | cut --delimiter=' ' --fields=1)"
      printf ' '"$(sha256sum Packages.gz | cut --delimiter=' ' --fields=1)"' %16d Packages.gz\n' \
             "$(wc --bytes Packages.gz | cut --delimiter=' ' --fields=1)"
      printf ' '"$(sha256sum Sources | cut --delimiter=' ' --fields=1)"' %16d Sources\n' \
             "$(wc --bytes Sources | cut --delimiter=' ' --fields=1)"
      printf ' '"$(sha256sum Sources.gz | cut --delimiter=' ' --fields=1)"' %16d Sources.gz\n' \
             "$(wc --bytes Sources.gz | cut --delimiter=' ' --fields=1)" ) >> Release
    gpg --armor --detach-sign --output Release.gpg Release
    cd -

    #
    # in build Ubuntu package each branch package is saved in a separated
    # directory with a well known name syntax to be able to use
    # correct dependencies during the "test Ubuntu package" procedure
    #
    if [ "$BUILD_REPOSITORY" -eq 1 -a -d "${GEM_DEB_REPO}" ]; then
        if [ "$branch" != "" ]; then
            repo_id="$(repo_id_get)"
            if [ "git://$repo_id" != "$GEM_GIT_REPO" -o "$branch" != "master" ]; then
                CUSTOM_SERIE="devel/$(echo "$repo_id" | sed "s@/@__@g;s/\./-/g")__${branch}"
                if [ "$CUSTOM_SERIE" != "" ]; then
                    GEM_DEB_SERIE="$CUSTOM_SERIE"
                fi
            fi
        fi
        mkdir -p "${GEM_DEB_REPO}/${BUILD_UBUVER}/${GEM_DEB_SERIE}"
        repo_tmpdir="$(mktemp -d "${GEM_DEB_REPO}/${BUILD_UBUVER}/${GEM_DEB_SERIE}/${GEM_DEB_PACKAGE}.${commit}.XXXXXX")"

        # if the monotone directory exists and is the "gem" repo and is the "master" branch then ...
        if [ -d "${GEM_DEB_MONOTONE}/${BUILD_UBUVER}/binary" ]; then
            if [ "git://$repo_id" == "$GEM_GIT_REPO" -a "$branch" == "master" ]; then
                cp ${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}_*.deb \
                   ${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}_*.changes \
                    ${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}_*.dsc ${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}_*.tar.?z \
                    "${GEM_DEB_MONOTONE}/${BUILD_UBUVER}/binary"
                PKG_COMMIT="$(git rev-parse HEAD | cut -c 1-7)"
                grep '_COMMIT' _jenkins_deps_info \
                  | sed 's/\(^.*=[0-9a-f]\{7\}\).*/\1/g' \
                  > "${GEM_DEB_MONOTONE}/${BUILD_UBUVER}/${GEM_DEB_PACKAGE}_${PKG_COMMIT}_deps.txt"
            fi
        fi

        cp ${GEM_BUILD_ROOT}/*.deb ${GEM_BUILD_ROOT}/*.changes \
           ${GEM_BUILD_ROOT}/*.dsc ${GEM_BUILD_ROOT}/*.tar.?z \
           ${GEM_BUILD_ROOT}/Packages* ${GEM_BUILD_ROOT}/Sources* \
           ${GEM_BUILD_ROOT}/Release* "${repo_tmpdir}" || true

        if [ "${GEM_DEB_REPO}/${BUILD_UBUVER}/${GEM_DEB_SERIE}/${GEM_DEB_PACKAGE}.${commit}" ]; then
            rm -rf "${GEM_DEB_REPO}/${BUILD_UBUVER}/${GEM_DEB_SERIE}/${GEM_DEB_PACKAGE}.${commit}"
        fi
        mv "${repo_tmpdir}" "${GEM_DEB_REPO}/${BUILD_UBUVER}/${GEM_DEB_SERIE}/${GEM_DEB_PACKAGE}.${commit}"
        echo "The package is saved here: ${GEM_DEB_REPO}/${BUILD_UBUVER}/${GEM_DEB_SERIE}/${GEM_DEB_PACKAGE}.${commit}"
    fi

    return $inner_ret
}



#
#  MAIN
#

BUILD_DEVEL=0
BUILD_FLAGS=""
BUILD_SOURCES_COPY=0
BUILD_REPOSITORY=0
UNSIGN_ARGS=""

trap sig_hand SIGINT SIGTERM
#  args management
while [ $# -gt 0 ]; do
    case $1 in
        -D|--development)
            BUILD_DEVEL=1
            if [ "$DEBFULLNAME" = "" -o "$DEBEMAIL" = "" ]; then
                echo
                echo "ERROR: set DEBFULLNAME and DEBEMAIL environment vars and run again the script"
                echo
                exit 1
            fi
            ;;

        -s|--serie)
            BUILD_UBUVER="$2"
            if [ "$BUILD_UBUVER" != "precise" -a "$BUILD_UBUVER" != "trusty"  -a "$BUILD_UBUVER" != "xenial" ]; then
                echo
                echo "ERROR: ubuntu version '$BUILD_UBUVER' not supported"
                echo
                exit 1
            fi
            BUILD_FLAGS="$BUILD_FLAGS $1"
            shift
            ;;

        -h|--help)
            usage 0
            break
            ;;

        -S|--sources_copy)
            BUILD_SOURCES_COPY=1
            ;;

        -R|--repository)
            BUILD_REPOSITORY=1
            ;;

        -U|--unsigned)
            UNSIGN_ARGS="-us -uc"
            ;;

        -h|--help)
            usage 0
            break
            ;;

        build)
            # Sed removes 'origin/' from the branch name
            build_run "$(echo "$2" | sed 's@.*/@@g')"
            break
            ;;

        *)
            usage 1
    esac
    shift
done

# if the monotone directory exists and is the "gem" repo and is the "master" branch then ...
if [ -d "${GEM_DEB_MONOTONE}/${BUILD_UBUVER}/source" -a $BUILD_SOURCES_COPY -eq 1 ]; then
    cp ${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}_*.changes \
        ${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}_*.dsc ${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}_*.tar.gz \
        "${GEM_DEB_MONOTONE}/${BUILD_UBUVER}/source"
fi
