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
# Provide the legacy x264 / x265 shared libraries that Apollo's PREBUILT
# ffmpeg (/opt/apollo/sysroot/lib/libavcodec.so) was linked against on Ubuntu
# 18.04 (bionic), namely:
#     libx264.so.155   (bionic libx264-152 package; SONAME is .so.155)
#     libx265.so.179   (bionic libx265-179 package)
#
# Why this exists:
#   Apollo's sysroot libavcodec.so is a bionic build. Its NEEDED entries point
#   at libx264.so.155 / libx265.so.179, AND it references VERSIONED symbols like
#   `x264_encoder_open_155` (x264 bakes its ABI rev into the symbol name). On
#   focal (20.04) the distro ships libx264.so.163 and on jammy (22.04) also
#   .so.163 / libx265.so.199 — different SONAME *and* different symbol suffix
#   (`x264_encoder_open_163`), so a simple symlink 163->155 does NOT work; the
#   undefined symbols are version-specific. Linking modules/drivers/video then
#   fails with:
#       libx264.so.155, needed by .../libavcodec.so, not found
#       undefined reference to `x264_encoder_open_155'
#
#   So we fetch the actual bionic libx264 / libx265 .deb files from the Ubuntu
#   ports/launchpad pool and unpack the .so.155 / .so.179 with `dpkg-deb -x`
#   (same trick as bvar / tensorrt). No apt solver, no version conflict with the
#   distro's own libx264-163; both can coexist because the SONAMEs differ.

set -e

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "${CURR_DIR}/installer_base.sh"

TARGET_ARCH="$(uname -m)"
if [[ "${TARGET_ARCH}" != "x86_64" ]]; then
    warning "install_ffmpeg_compat.sh only handles x86_64; skipping on ${TARGET_ARCH}."
    exit 0
fi

DEST_LIB="/usr/local/lib"
mkdir -p "${DEST_LIB}"

# Idempotency: if both legacy sonames already present, do nothing.
if ldconfig -p 2>/dev/null | grep -q "libx264.so.155" && \
   ldconfig -p 2>/dev/null | grep -q "libx265.so.179"; then
    ok "Legacy libx264.so.155 / libx265.so.179 already present; nothing to do."
    exit 0
fi

# bionic (18.04) main/universe pool. These URLs are the public Ubuntu archive;
# the China mirror (mirrors.aliyun.com) is faster domestically. Override with
# FFMPEG_COMPAT_BASEURL if needed.
# Ubuntu universe pool has a first-letter subdir: pool/universe/x/x264/...
DEFAULT_BASEURL="https://mirrors.aliyun.com/ubuntu/pool/universe/x"
FFMPEG_COMPAT_BASEURL="${FFMPEG_COMPAT_BASEURL:-${DEFAULT_BASEURL}}"

# Package files that ship the exact SONAMEs Apollo's prebuilt ffmpeg needs.
# The package's trailing number == the SONAME number:
#   libx264-155 -> libx264.so.155
#   libx265-179 -> libx265.so.179
# (Verified present in the aliyun universe pool listing.)
X264_DEB="x264/libx264-155_0.155.2917+git0a84d98-2_amd64.deb"
X265_DEB="x265/libx265-179_3.2.1-1build1_amd64.deb"

_workdir="$(mktemp -d)"
trap 'rm -rf "${_workdir}"' EXIT

_fetch_and_extract() {
    local rel="$1"; local soname="$2"
    local url="${FFMPEG_COMPAT_BASEURL}/${rel}"
    local fn="${_workdir}/$(basename "${rel}")"
    info "Fetching ${soname} from ${url}"
    if ! curl -fSL --retry 3 --connect-timeout 15 -o "${fn}" "${url}"; then
        warning "Download failed: ${url}"
        return 1
    fi
    # Extract just the .so* files into a temp root, then copy the versioned
    # library into /usr/local/lib (keeps it separate from the distro's libx264).
    rm -rf "${_workdir}/root" && mkdir -p "${_workdir}/root"
    dpkg-deb -x "${fn}" "${_workdir}/root"
    local found
    found="$(find "${_workdir}/root" -name "${soname}*" -type f | head -n1)"
    if [[ -z "${found}" ]]; then
        # Some debs ship a symlink + real file; grab the real .so.* file.
        found="$(find "${_workdir}/root" -name "${soname}" | head -n1)"
    fi
    if [[ -z "${found}" ]]; then
        warning "${soname} not found inside $(basename "${rel}")"
        return 1
    fi
    cp -av "${found}" "${DEST_LIB}/"
    # Recreate the bare SONAME symlink if the deb shipped a real file with a
    # longer name.
    local base
    base="$(basename "${found}")"
    if [[ "${base}" != "${soname}" ]]; then
        ln -sfn "${base}" "${DEST_LIB}/${soname}"
    fi
    return 0
}

_ok264=1
if ! ldconfig -p 2>/dev/null | grep -q "libx264.so.155"; then
    _fetch_and_extract "${X264_DEB}" "libx264.so.155" || _ok264=0
fi
_ok265=1
if ! ldconfig -p 2>/dev/null | grep -q "libx265.so.179"; then
    _fetch_and_extract "${X265_DEB}" "libx265.so.179" || _ok265=0
fi

ldconfig

if [[ "${_ok264}" -ne 1 || "${_ok265}" -ne 1 ]]; then
    error "Failed to provide one of the legacy ffmpeg codec libs."
    error "x264.so.155 ok=${_ok264}, x265.so.179 ok=${_ok265}"
    error "Set FFMPEG_COMPAT_BASEURL to a reachable bionic universe pool, or"
    error "place the .so files manually under ${DEST_LIB} and run ldconfig."
    error "Pool tried: ${FFMPEG_COMPAT_BASEURL}"
    exit 1
fi

info "Installed legacy codec libs into ${DEST_LIB}:"
ldconfig -p | grep -E "libx264.so.155|libx265.so.179" || true
ok "Successfully provided libx264.so.155 / libx265.so.179 for Apollo's prebuilt ffmpeg."