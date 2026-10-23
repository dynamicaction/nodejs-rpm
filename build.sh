#!/bin/bash
# Build the RPMs from a tree staged by prepare-sources.sh, inside an
# amazonlinux:2023 container pinned to the releasever the target hosts run,
# so the packages link against the same system libraries.
#
# Usage: ./build.sh <releasever, e.g. 2023.12.20260803> [work dir]
# Needs docker on x86_64 (build1.dev1: run with sudo). Takes ~75 min on 6 CPUs.
set -euo pipefail

releasever=${1:?usage: $0 <releasever> [work dir]}
work=${2:-$PWD/work}
cpus=${CPUS:-6}

docker run --rm --cpus="$cpus" -v "$work/rpmbuild:/build" amazonlinux:2023 bash -euxo pipefail -c "
    dnf -y --releasever=$releasever install rpm-build 'dnf-command(builddep)'
    dnf -y --releasever=$releasever builddep /build/SPECS/nodejs22.spec
    rpmbuild --define '_topdir /build' -ba /build/SPECS/nodejs22.spec
    chown -R ${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)} /build
" 2>&1 | tee "$work/build.log"

ls -l "$work"/rpmbuild/RPMS/*/ "$work"/rpmbuild/SRPMS/
