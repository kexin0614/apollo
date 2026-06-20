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
# Install NVIDIA TensorRT for the modern (u20/u22) CUDA dev images.
#
# Why this exists:
#   The base image `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04` ships CUDA +
#   cuDNN but NOT TensorRT. Apollo's `tools/bootstrap.py` (./apollo.sh config),
#   however, FORCES `TF_NEED_TENSORRT=1` whenever stage=dev and TF_NEED_CUDA=1
#   (see bootstrap.py ~line 1202). In non-interactive mode `validate_cuda_config`
#   then runs `third_party/gpus/find_cuda_config.py ... tensorrt`, looks for
#   `NvInferVersion.h` + `libnvinfer.so`, fails to find them and aborts with:
#       Could not find any NvInferVersion.h matching version ''
#       [ERROR] Cannot validate_cuda_config non-interactively. Aborting ...
#
#   `find_cuda_config.py` searches the standard apt layout
#   (`/usr/include/x86_64-linux-gnu/NvInfer*.h` and
#    `/usr/lib/x86_64-linux-gnu/libnvinfer.so*`), so installing the official
#   NVIDIA TensorRT debs is enough — no special path juggling required.
#
# Install strategy (IMPORTANT — learnt the hard way):
#   We do NOT use `apt install`. The NVIDIA cuda apt repo now serves TensorRT
#   8.x AND 10.x, each in both +cuda11.8 and +cuda12.x flavors, and apt's
#   dependency solver simply cannot keep a TRT8/cu11.8 set self-consistent:
#       libnvinfer-dev : Depends: libnvinfer-headers-dev (= 8.6.1.6-1+cuda11.8)
#                        but 10.13.0.35-1+cuda12.9 is to be installed
#                        Depends: libnvinfer8 (= 8.6.1.6-1+cuda11.8)
#                        but 8.6.1.6-1+cuda12.0 is to be installed
#   i.e. even with `=8.6.1.6-1+cuda11.8` pins, apt keeps trying to pull the
#   cu12.0 / TRT10 builds of the *transitive* deps and bails with
#   "held broken packages".
#
#   Instead we download the exact `.deb` files straight from NVIDIA's PUBLIC
#   CDN pool (NO account / login required — these are the very files the apt
#   repo serves) and unpack them with `dpkg-deb -x /` — the same trick we use
#   for `bvar`. This bypasses the dependency solver entirely; we choose the
#   precise cu11.8 SONAME-8 set ourselves, so there is nothing to "resolve".
#
#   Layout after unpack matches what find_cuda_config.py wants:
#     headers -> /usr/include/x86_64-linux-gnu/NvInfer*.h
#     libs    -> /usr/lib/x86_64-linux-gnu/libnvinfer.so*
#
# Override knobs (env / args):
#   TRT_VERSION      full TRT version (default: 8.6.1.6)
#   TRT_CUDA_TAG     cuda suffix (default: auto from CUDA_VERSION -> cuda11.8)
#   TRT_DEB_BASEURL  override the .deb pool base URL
#   SKIP_TENSORRT=1  skip entirely (e.g. CPU-only image); leaves config to fail
#                    loudly unless you also pass TF_NEED_TENSORRT=0 to config.

set -e

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "${CURR_DIR}/installer_base.sh"

TARGET_ARCH="$(uname -m)"
TRT_VERSION="${TRT_VERSION:-8.6.1.6}"
TRT_MAJOR="${TRT_VERSION%%.*}"

if [[ "${SKIP_TENSORRT:-0}" == "1" ]]; then
    info "SKIP_TENSORRT=1 -> skipping TensorRT installation."
    exit 0
fi

if [[ "${TARGET_ARCH}" != "x86_64" ]]; then
    warning "install_tensorrt.sh currently only supports x86_64; got ${TARGET_ARCH}." \
            "Skipping (aarch64/Jetson ships TensorRT via JetPack)."
    exit 0
fi

# Idempotency: if libnvinfer headers + lib already present, do nothing.
if [[ -f /usr/include/x86_64-linux-gnu/NvInferVersion.h ]] && \
   ldconfig -p 2>/dev/null | grep -q "libnvinfer.so"; then
    _ver="$(awk '/NV_TENSORRT_MAJOR/{print $3; exit}' \
            /usr/include/x86_64-linux-gnu/NvInferVersion.h 2>/dev/null || echo '?')"
    ok "TensorRT already installed (major=${_ver}); nothing to do."
    exit 0
fi

. /etc/os-release || true
CODENAME="${VERSION_CODENAME:-focal}"

# Decide which "+cudaXX.Y" flavor to match. The u20 image is CUDA 11.8, so we
# want the cu11.8 build; u22 is CUDA 12.x.
if [[ -z "${TRT_CUDA_TAG:-}" ]]; then
    case "${CUDA_VERSION:-}" in
        11.*) TRT_CUDA_TAG="cuda11.8" ;;
        12.*) TRT_CUDA_TAG="cuda12.0" ;;
        *)    TRT_CUDA_TAG="cuda11.8" ;;   # safe default for the u20 image
    esac
fi

# The exact apt version string baked into the .deb file names, e.g.
# "8.6.1.6-1+cuda11.8". (deb filename uses this verbatim.)
DEB_VER="${TRT_VERSION}-1+${TRT_CUDA_TAG}"

# Public NVIDIA CUDA repo pool. The cn mirror (developer.download.nvidia.cn) is
# faster in China and is already trusted in these images; fall back to .com.
# Both serve the identical pool with NO login.
case "${TARGET_ARCH}" in
    x86_64) REPO_ARCH="x86_64" ;;
    *)      REPO_ARCH="${TARGET_ARCH}" ;;
esac
DEFAULT_BASEURL="https://developer.download.nvidia.cn/compute/cuda/repos/ubuntu2004/${REPO_ARCH}"
TRT_DEB_BASEURL="${TRT_DEB_BASEURL:-${DEFAULT_BASEURL}}"

info "Installing TensorRT ${TRT_VERSION} (+${TRT_CUDA_TAG}) for ${CODENAME}" \
     "(CUDA ${CUDA_VERSION:-unknown}) via direct .deb unpack ..."
info "Pool: ${TRT_DEB_BASEURL}"

# The TRT8 set is split across these packages. We download+unpack them with
# dpkg-deb (NOT apt install) precisely so the cu11.8 / TRT8 versions never get
# "resolved" into cu12 / TRT10 by apt's dependency solver.
#
# NOTE on nvparsers: it was removed in TensorRT 10, but Apollo's perception
# (modules/perception/common/inference/tensorrt/rt_common.h) still
# `#include "NvCaffeParser.h"`, so on this TRT8.6 image we MUST install the
# nvparsers headers + lib. Because we bypass apt's solver via dpkg-deb -x, the
# old "libnvparsers-dev depends on cu12 libnvinfer-dev" conflict that broke the
# apt path does NOT apply here — we just drop the exact cu11.8 files in place.
TRT_DEBS=(
    "libnvinfer8_${DEB_VER}_amd64.deb"
    "libnvinfer-dev_${DEB_VER}_amd64.deb"
    "libnvinfer-headers-dev_${DEB_VER}_amd64.deb"
    "libnvinfer-plugin8_${DEB_VER}_amd64.deb"
    "libnvinfer-plugin-dev_${DEB_VER}_amd64.deb"
    "libnvinfer-headers-plugin-dev_${DEB_VER}_amd64.deb"
    "libnvonnxparsers8_${DEB_VER}_amd64.deb"
    "libnvonnxparsers-dev_${DEB_VER}_amd64.deb"
    "libnvparsers8_${DEB_VER}_amd64.deb"
    "libnvparsers-dev_${DEB_VER}_amd64.deb"
)

_workdir="$(mktemp -d)"
trap 'rm -rf "${_workdir}"' EXIT

_dl_ok=1
for _deb in "${TRT_DEBS[@]}"; do
    _url="${TRT_DEB_BASEURL}/${_deb}"
    info "Downloading ${_deb}"
    if ! curl -fSL --retry 3 --connect-timeout 15 -o "${_workdir}/${_deb}" "${_url}"; then
        warning "Failed to download ${_url}"
        _dl_ok=0
        break
    fi
done

if [[ "${_dl_ok}" -ne 1 ]]; then
    error "Could not download the TensorRT ${DEB_VER} .deb set from:"
    error "  ${TRT_DEB_BASEURL}"
    error "Check that TRT_VERSION/TRT_CUDA_TAG match an existing build, or set"
    error "TRT_DEB_BASEURL to a reachable mirror. You can list the pool at:"
    error "  ${TRT_DEB_BASEURL}/  (browse for libnvinfer*_${TRT_VERSION}-*.deb)"
    exit 1
fi

# Unpack every .deb onto / — no dpkg dependency checks, no apt solver.
for _deb in "${TRT_DEBS[@]}"; do
    info "Unpacking ${_deb}"
    dpkg-deb -x "${_workdir}/${_deb}" /
done

# Verify the layout find_cuda_config.py expects.
if [[ ! -f /usr/include/x86_64-linux-gnu/NvInferVersion.h ]]; then
    # Some older TRT packaging keeps headers under /usr/include directly.
    if [[ -f /usr/include/NvInferVersion.h ]]; then
        warning "NvInferVersion.h found under /usr/include (not the -linux-gnu" \
                "subdir); find_cuda_config.py searches both, so this is fine."
    else
        error "TensorRT installed but NvInferVersion.h not found in the expected" \
              "locations. find_cuda_config.py will still fail."
        exit 1
    fi
fi

ldconfig

TRT_VER="$(awk '/NV_TENSORRT_MAJOR/{maj=$3} /NV_TENSORRT_MINOR/{min=$3} \
                /NV_TENSORRT_PATCH/{pat=$3} END{printf "%s.%s.%s", maj, min, pat}' \
           /usr/include/x86_64-linux-gnu/NvInferVersion.h 2>/dev/null \
           || echo 'unknown')"

ok "Successfully installed TensorRT ${TRT_VER}"
info "Headers: /usr/include/x86_64-linux-gnu/NvInfer*.h"
info "Libs   : $(ldconfig -p | grep -m1 'libnvinfer.so' | awk '{print $NF}')"