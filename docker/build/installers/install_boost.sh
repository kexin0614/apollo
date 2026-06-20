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

# Fail on first error.
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"
. ./installer_base.sh

if ldconfig -p | grep -q "libboost_system.so" ; then
    info "Found existing Boost installation. Reinstallation skipped."
    exit 0
fi

# PreReq for Unicode support for Boost.Regex
#    icu-devtools \
#    libicu-dev
apt_get_update_and_install \
    liblzma-dev \
    libbz2-dev \
    libzstd-dev

# Ref: https://www.boost.org/
VERSION="1_74_0"
DOTTED_VERSION="${VERSION//_/.}"

PKG_NAME="boost_${VERSION}.tar.bz2"
CHECKSUM="83bfc1507731a0906e387fc28b7ef5417d591429e51e788417fe9ff025e116b1"

# NOTE(modern-fix): the original boostorg.jfrog.io artifactory was retired by
# JFrog around 2024; every request 302-redirects to a ~11KB landing page so
# `download_if_not_cached` happily "succeeds" but tar-bzip2 then dies with
# "is not a bzip2 file". We try a list of currently-online mirrors in order
# and verify the SHA256 ourselves (installer_base only checksums the local
# HTTP-cache hit path, not the remote download path).
MIRRORS=(
  # Apollo's own bcebos CDN -- fastest in CN, kept online for legacy 6.0 builds
  "https://apollo-system.cdn.bcebos.com/archive/6.0/${PKG_NAME}"
  # Boost official new home (global CDN, replaces jfrog)
  "https://archives.boost.io/release/${DOTTED_VERSION}/source/${PKG_NAME}"
  # aliyun BLFS mirror -- very fast in CN, occasionally lagging
  "https://mirrors.aliyun.com/blfs/conglomeration/boost/${PKG_NAME}"
  # SourceForge fallback -- slow but extremely durable
  "https://sourceforge.net/projects/boost/files/boost/${DOTTED_VERSION}/${PKG_NAME}/download"
)

download_ok=0
for url in "${MIRRORS[@]}"; do
  rm -f "${PKG_NAME}"
  info "Trying boost mirror: ${url}"
  # -L: follow redirects (sourceforge needs this); --fail: HTTP >=400 → error
  if curl -fL --retry 3 --retry-delay 2 -o "${PKG_NAME}" "${url}"; then
    actual_cs=$(/usr/bin/sha256sum "${PKG_NAME}" | awk '{print $1}')
    if [[ "${actual_cs}" == "${CHECKSUM}" ]]; then
      ok "Successfully downloaded ${PKG_NAME} from ${url}"
      download_ok=1
      break
    else
      warning "Checksum mismatch from ${url} (got ${actual_cs}); trying next mirror"
    fi
  else
    warning "Download failed from ${url}; trying next mirror"
  fi
done

if [[ "${download_ok}" -ne 1 ]]; then
  error "Failed to download ${PKG_NAME} from all known mirrors. " \
        "If you are behind a corporate proxy, set http_proxy/https_proxy " \
        "before running docker build, or pre-populate \${LOCAL_HTTP_ADDR}."
  exit 1
fi

tar xjf "${PKG_NAME}"

py3_ver="$(py3_version)"

# Ref: https://www.boost.org/doc/libs/1_73_0/doc/html/mpi/getting_started.html
pushd "boost_${VERSION}"
    # A) For mpi built from source
    #  echo "using mpi : ${SYSROOT_DIR}/bin/mpicc ;" > user-config.jam
    # B) For mpi installed via apt
    # echo "using mpi ;" > user-config.jam
    ./bootstrap.sh \
        --with-python-version=${py3_ver} \
        --prefix="${SYSROOT_DIR}" \
        --without-icu

    ./b2 -d+2 -q -j$(nproc) \
        --without-graph_parallel \
        --without-mpi \
        variant=release \
        link=shared \
        threading=multi \
        install
        #--user-config=user-config.jam
popd
ldconfig

# Clean up
rm -rf "boost_${VERSION}" "${PKG_NAME}"

if [[ -n "${CLEAN_DEPS}" ]]; then
    apt_get_remove  \
        liblzma-dev \
        libbz2-dev \
        libzstd-dev
fi

