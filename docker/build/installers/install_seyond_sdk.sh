#!/usr/bin/env bash

###############################################################################
# Copyright 2024 The Apollo Authors. All Rights Reserved.
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
#
# Install the Seyond (Innovusion) lidar client SDK so that
# modules/drivers/lidar/seyond can compile.
#
# Tarball (inno-lidar-sdk-release-client-sdk-3.103.10-public.tgz) layout:
#   src/sdk_common/inno_lidar_api.h , inno_lidar_other_api.h ,
#                  inno_lidar_packet.h , inno_lidar_packet_utils.h , ...
#   src/utils/*.h        (log.h, utils.h, ... — included by sdk_common headers)
#   src/sdk_client/*.h
#   lib/libinnolidarsdkclient.so(.3/.3.x)   + .a
#   lib/libinnolidarsdkcommon.so(.3/.3.x)   + .a
#   lib/libinnolidarutils.so(.3/.3.x)       + .a
#
# Apollo's seyond driver does:
#   #include "seyond/sdk_common/inno_lidar_api.h"   (4 headers, all sdk_common)
#   linkopts = ["-linnoclientsdk"]                  (OLD single-lib name)
#
# Two mismatches we must bridge:
#   1) header prefix: driver uses `seyond/sdk_common/...`, but the SDK headers
#      internally include WITHOUT that prefix (e.g. `#include "utils/log.h"` or
#      `#include "sdk_common/inno_lidar_packet.h"`). So we expose the SDK src
#      headers under BOTH:
#         /opt/apollo/sysroot/include/seyond/{sdk_common,utils,sdk_client}/...
#         /opt/apollo/sysroot/include/{sdk_common,utils,sdk_client}/...
#   2) lib name: the driver links `-linnoclientsdk`, but 3.x renamed the libs to
#      libinnolidarsdkclient / libinnolidarsdkcommon / libinnolidarutils. We
#      install all three AND create a compatibility symlink
#      libinnoclientsdk.so -> libinnolidarsdkclient.so so the existing
#      `-linnoclientsdk` keeps resolving. (modules/drivers/lidar/seyond/BUILD is
#      also updated to link the three real libs as the primary path.)
#
# Override knobs:
#   SEYOND_SDK_URL       full tarball URL (default: 3.103.10 public client SDK)
#   SEYOND_SDK_SHA256    optional sha256 to verify the tarball
#   SKIP_SEYOND_SDK=1    skip (only valid if you also drop the seyond package)

set -e

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "${CURR_DIR}/installer_base.sh"

if [[ "${SKIP_SEYOND_SDK:-0}" == "1" ]]; then
    info "SKIP_SEYOND_SDK=1 -> skipping Seyond SDK installation."
    exit 0
fi

TARGET_ARCH="$(uname -m)"
if [[ "${TARGET_ARCH}" != "x86_64" ]]; then
    warning "install_seyond_sdk.sh currently only handles x86_64; skipping on ${TARGET_ARCH}."
    exit 0
fi

SYSROOT="${SYSROOT_DIR:-/opt/apollo/sysroot}"
SYSROOT_INC="${SYSROOT}/include"
SYSROOT_LIB="${SYSROOT}/lib"
mkdir -p "${SYSROOT_INC}" "${SYSROOT_LIB}"

# Idempotency.
if [[ -f "${SYSROOT_INC}/seyond/sdk_common/inno_lidar_api.h" ]] && \
   ls "${SYSROOT_LIB}"/libinnolidarsdkclient.so* >/dev/null 2>&1; then
    ok "Seyond SDK already installed under ${SYSROOT}; nothing to do."
    exit 0
fi

SEYOND_SDK_VERSION="3.103.10"
DEFAULT_URL="https://github.com/Seyond-Inc/inno-lidar-sdk/releases/download/${SEYOND_SDK_VERSION}/inno-lidar-sdk-release-client-sdk-${SEYOND_SDK_VERSION}-public.tgz"
SEYOND_SDK_URL="${SEYOND_SDK_URL:-${DEFAULT_URL}}"

_workdir="$(mktemp -d)"
trap 'rm -rf "${_workdir}"' EXIT

PKG_NAME="$(basename "${SEYOND_SDK_URL}")"
info "Downloading Seyond SDK ${SEYOND_SDK_VERSION} from ${SEYOND_SDK_URL}"
if ! curl -fSL --retry 3 --connect-timeout 20 -o "${_workdir}/${PKG_NAME}" "${SEYOND_SDK_URL}"; then
    error "Failed to download Seyond SDK from ${SEYOND_SDK_URL}"
    error "If GitHub is unreachable, set SEYOND_SDK_URL to a mirror, e.g.:"
    error "  SEYOND_SDK_URL=https://ghproxy.com/${SEYOND_SDK_URL}"
    exit 1
fi

if [[ -n "${SEYOND_SDK_SHA256:-}" ]]; then
    echo "${SEYOND_SDK_SHA256}  ${_workdir}/${PKG_NAME}" | sha256sum -c - \
        || { error "Seyond SDK checksum mismatch"; exit 1; }
fi

EXTRACT_DIR="${_workdir}/extract"
mkdir -p "${EXTRACT_DIR}"
tar -xzf "${_workdir}/${PKG_NAME}" -C "${EXTRACT_DIR}"

# Locate the SDK "src" dir (the one that contains sdk_common/inno_lidar_api.h).
_api_hdr="$(find "${EXTRACT_DIR}" -type f -path '*sdk_common/inno_lidar_api.h' | head -n1)"
if [[ -z "${_api_hdr}" ]]; then
    error "sdk_common/inno_lidar_api.h not found inside ${PKG_NAME}."
    error "  tar tzf ${PKG_NAME} | grep -E 'inno_lidar_api.h|libinnolidar'"
    exit 1
fi
_sdk_common_dir="$(dirname "${_api_hdr}")"       # .../src/sdk_common
_src_dir="$(dirname "${_sdk_common_dir}")"       # .../src
info "SDK src dir : ${_src_dir}"

# Install headers under BOTH seyond/<dir> and <dir> at the sysroot include root.
# We copy every header-bearing subdir of src/ (sdk_common, utils, sdk_client).
mkdir -p "${SYSROOT_INC}/seyond"
_install_hdr_dir() {
    local d="$1"
    local base
    base="$(basename "${d}")"
    # under seyond/ (for the driver's `seyond/sdk_common/...` includes)
    rm -rf "${SYSROOT_INC}/seyond/${base}"
    mkdir -p "${SYSROOT_INC}/seyond/${base}"
    find "${d}" \( -name '*.h' -o -name '*.hpp' \) -print0 \
        | while IFS= read -r -d '' f; do
            rel="${f#${d}/}"
            mkdir -p "${SYSROOT_INC}/seyond/${base}/$(dirname "${rel}")"
            cp -a "${f}" "${SYSROOT_INC}/seyond/${base}/${rel}"
          done
    # at the include root (for the SDK headers' own prefix-less includes)
    rm -rf "${SYSROOT_INC}/${base}"
    mkdir -p "${SYSROOT_INC}/${base}"
    find "${d}" \( -name '*.h' -o -name '*.hpp' \) -print0 \
        | while IFS= read -r -d '' f; do
            rel="${f#${d}/}"
            mkdir -p "${SYSROOT_INC}/${base}/$(dirname "${rel}")"
            cp -a "${f}" "${SYSROOT_INC}/${base}/${rel}"
          done
}

for sub in sdk_common utils sdk_client; do
    if [[ -d "${_src_dir}/${sub}" ]]; then
        info "Installing headers: ${sub}/"
        _install_hdr_dir "${_src_dir}/${sub}"
    fi
done

# Install the prebuilt shared libs (and their versioned symlinks) + static libs.
_lib_src="$(find "${EXTRACT_DIR}" -type d -name lib | head -n1)"
if [[ -z "${_lib_src}" ]]; then
    error "lib/ dir not found inside ${PKG_NAME}."
    exit 1
fi
info "SDK lib dir : ${_lib_src}"
# cp -a preserves the .so -> .so.3 -> .so.3.x symlink chain.
cp -a "${_lib_src}"/libinnolidarsdkclient.* "${SYSROOT_LIB}/" 2>/dev/null || true
cp -a "${_lib_src}"/libinnolidarsdkcommon.* "${SYSROOT_LIB}/" 2>/dev/null || true
cp -a "${_lib_src}"/libinnolidarutils.*     "${SYSROOT_LIB}/" 2>/dev/null || true

# Backward-compat symlink for the old `-linnoclientsdk` link flag: point it at
# the client lib. (BUILD is updated to link all three explicitly, but this keeps
# any stale `-linnoclientsdk` reference working too.)
if [[ -e "${SYSROOT_LIB}/libinnolidarsdkclient.so" ]]; then
    ln -sfn libinnolidarsdkclient.so "${SYSROOT_LIB}/libinnoclientsdk.so"
fi

ldconfig || true

# Verify.
[[ -f "${SYSROOT_INC}/seyond/sdk_common/inno_lidar_api.h" ]] \
    || { error "Header not at ${SYSROOT_INC}/seyond/sdk_common/inno_lidar_api.h"; exit 1; }
ls "${SYSROOT_LIB}"/libinnolidarsdkclient.so* >/dev/null 2>&1 \
    || { error "libinnolidarsdkclient.so* not installed under ${SYSROOT_LIB}"; exit 1; }

info "Headers : ${SYSROOT_INC}/seyond/{sdk_common,utils,sdk_client}/"
info "Libs    : $(ls ${SYSROOT_LIB}/libinnolidar*.so 2>/dev/null | tr '\n' ' ')"
ok "Successfully installed Seyond SDK ${SEYOND_SDK_VERSION}"