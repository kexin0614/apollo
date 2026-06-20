#!/usr/bin/env bash
###############################################################################
# Copyright 2020 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"
. ./installer_base.sh

apt_get_update_and_install \
    ca-certificates \
    curl \
    gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apollo-pkg-beta.cdn.bcebos.com/neo/beta/key/deb.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/apolloauto.gpg
sudo chmod a+r /etc/apt/keyrings/apolloauto.gpg

# ----------------------------------------------------------------------------
# Apollo's package repo (https://apollo-pkg-beta.cdn.bcebos.com/apollo/core)
# only publishes content under the `bionic` codename. On Ubuntu 18.04 we
# can use $VERSION_CODENAME directly; on focal/jammy that suite does not
# exist on the server, which makes `apt-get update` either error out (no
# Release file) or silently drop the entire source. Either way, the next
# `apt install bvar` step would fail with:
#     E: Package 'bvar' has no installation candidate
#
# Strategy on focal/jammy:
#   1) Pin the apolloauto apt source to `bionic` so `apt-get update` succeeds
#      (the deb files inside only depend on libc6, which is ABI-compatible
#      across bionic -> focal -> jammy).
#   2) DON'T `apt install bvar` — its Depends string is bionic-specific.
#      Instead call our `install_bvar.sh` helper, which fetches the bionic
#      .deb directly and `dpkg-deb -x`-extracts the payload. That helper is
#      idempotent: on cyber-stage builds bvar is already installed, so it
#      no-ops.
# ----------------------------------------------------------------------------
SRC_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
APOLLO_REPO_CODENAME="${SRC_CODENAME}"
case "${SRC_CODENAME}" in
    focal|jammy)
        APOLLO_REPO_CODENAME="bionic"
        info "install_pkg_repo.sh: pinning apolloauto apt repo to 'bionic' (host is ${SRC_CODENAME})."
        ;;
esac

echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/apolloauto.gpg] https://apollo-pkg-beta.cdn.bcebos.com/apollo/core"\
    "${APOLLO_REPO_CODENAME}" "main" | \
    sudo tee /etc/apt/sources.list.d/apolloauto.list
sudo apt-get update || warning "apt-get update reported errors after adding apolloauto repo; continuing."

if [[ "${SRC_CODENAME}" == "bionic" ]]; then
    apt_get_update_and_install bvar
else
    info "install_pkg_repo.sh: skipping 'apt install bvar' on ${SRC_CODENAME}; using install_bvar.sh fallback instead."
    bash "$(dirname "${BASH_SOURCE[0]}")/install_bvar.sh"
fi

mkdir -p /opt/apollo/neo/data/log && chmod -R 777 /opt/apollo/neo

echo "[[ -e /opt/apollo/neo/setup.sh ]] && source /opt/apollo/neo/setup.sh" >> /etc/skel/.bashrc

if [[ -f /usr/include/flann/util/params.h ]]; then
    sed -i 's/#include "flann\/general\.h"/#include <\/usr\/include\/flann\/general\.h>/g' /usr/include/flann/util/params.h
else
    warning "install_pkg_repo.sh: /usr/include/flann/util/params.h not found; skipping flann include rewrite."
fi
