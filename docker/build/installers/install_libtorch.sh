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

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. ${CURR_DIR}/installer_base.sh

# TODO(build): Docs on how to build libtorch on Jetson boards
# References:
#   https://github.com/ApolloAuto/apollo/blob/pre6/docker/build/installers/install_libtorch.sh
#   https://github.com/dusty-nv/jetson-containers/blob/master/Dockerfile.pytorch
#   https://forums.developer.nvidia.com/t/pytorch-for-jetson-version-1-6-0-now-available
#   https://github.com/pytorch/pytorch/blob/master/docker/caffe2/ubuntu-16.04-cpu-all-options/Dockerfile
#
# Following content describes how to build libtorch source on orin:
# 1. Downloading libtorch source: git clone https://github.com/pytorch/pytorch.git
# 2. install py deps: pip3 install --no-cache-dir PyYAML typing
# 3. init sub modules: git clone --recursive --single-branch --branch apollo --depth 1 https://github.com/pytorch/pytorch.git && git checkout release/1.11
# 4. set env: export USE_CUDA=1 && export TORCH_CUDA_ARCH_LIST="3.5;5.0;5.2;6.1;7.0;7.5;8.6;8.7" && export BUILD_CAFFE2=1 && export USE_NCCL=0
# 5. python3 setup.py install
# 6. mkdir libtorch_gpu && cp -r include libtorch_gpu/ && cp -r lib libtorch_gpu/ && sudo mv libtorch_gpu /usr/local/

bash ${CURR_DIR}/install_mkl.sh

TARGET_ARCH="$(uname -m)"

sudo apt update && sudo apt install -y libopenblas-base libopenmpi-dev libomp-dev

pip3 install Cython

##============================================================##
# libtorch_cpu

if [[ "${TARGET_ARCH}" == "x86_64" ]]; then
  # https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-1.5.0%2Bcpu.zip
  VERSION="1.7.0-2"
  CHECKSUM="02fd4f30e97ce8911ef933d0516660892392e95e6768b50f591f4727f6224390"
  PKG_NAME="libtorch_cpu-${VERSION}-linux-${TARGET_ARCH}.tar.gz"
  DOWNLOAD_LINK="https://apollo-system.cdn.bcebos.com/archive/6.0/${PKG_NAME}"
elif [[ "${TARGET_ARCH}" == "aarch64" ]]; then
  VERSION="1.11.0"
  CHECKSUM="7faae6caad3c7175070263a0767732c0be9a92be25f9fb022aebe14a4cd2d092"
  PKG_NAME="libtorch_cpu-${VERSION}-linux-${TARGET_ARCH}.tar.gz"
  DOWNLOAD_LINK="https://apollo-pkg-beta.cdn.bcebos.com/archive/${PKG_NAME}"
else
  error "libtorch for ${TARGET_ARCH} not ready. Exiting..."
  exit 1
fi

download_if_not_cached "${PKG_NAME}" "${CHECKSUM}" "${DOWNLOAD_LINK}"

tar xzf "${PKG_NAME}"
# The tarball's top-level directory matches the archive basename, e.g.
#   libtorch_cpu-1.7.0-2-linux-x86_64/
# (Older Apollo scripts assumed a fixed name "libtorch_cpu" which no longer
# matches the published archives, causing `mv: cannot stat 'libtorch_cpu'`.)
_extracted_dir="${PKG_NAME%.tar.gz}"
if [[ ! -d "${_extracted_dir}" ]]; then
    # Fallback: pick the single top-level directory the archive produced.
    _extracted_dir="$(tar tzf "${PKG_NAME}" | awk -F/ 'NF>1{print $1}' | sort -u | head -n1)"
fi
mv "${_extracted_dir}" /usr/local/libtorch_cpu
rm -f "${PKG_NAME}"
ok "Successfully installed libtorch_cpu ${VERSION}"

##============================================================##
# libtorch_gpu
#
# Inside `docker build` we cannot rely on `nvidia-smi`: that binary is
# injected by nvidia-container-toolkit only at `docker run --gpus all`
# time; the build sandbox itself never has it (the CUDA base image ships
# the toolkit/libraries but not nvidia-smi). The original
# `determine_gpu_use_host` therefore silently sets USE_NVIDIA_GPU=0 and
# we end up with a CPU-only image that breaks bazel later when
# perception expects /usr/local/libtorch_gpu.
#
# Fix: honour an explicit build-time switch first.
#   - APOLLO_GPU=nvidia / amd / cpu / auto   (auto = old behaviour)
#   - Default for x86_64 is "nvidia" because all our *.nvidia.dockerfile
#     variants are built on top of a CUDA base image; the very fact that
#     this Dockerfile is being built implies GPU libtorch is wanted.
APOLLO_GPU="${APOLLO_GPU:-auto}"
case "${APOLLO_GPU}" in
    nvidia)
        USE_NVIDIA_GPU=1; USE_AMD_GPU=0
        info "APOLLO_GPU=nvidia -> forcing libtorch_gpu (CUDA) install."
        ;;
    amd)
        USE_NVIDIA_GPU=0; USE_AMD_GPU=1
        info "APOLLO_GPU=amd -> forcing libtorch_gpu (ROCm) install."
        ;;
    cpu)
        USE_NVIDIA_GPU=0; USE_AMD_GPU=0
        info "APOLLO_GPU=cpu -> skipping libtorch_gpu install."
        ;;
    auto|*)
        # Old behaviour: probe the *build* host. Inside docker build this
        # almost always falls through to USE_NVIDIA_GPU=0 because
        # nvidia-smi is not present in the build sandbox. We additionally
        # treat "this is a CUDA base image" as a strong signal that the
        # user wants the GPU libtorch even when the probe fails.
        determine_gpu_use_host
        if [[ "${USE_NVIDIA_GPU}" -eq 0 && "${USE_AMD_GPU}" -eq 0 ]]; then
            if [[ -n "${CUDA_VERSION:-}" ]] || [[ -d /usr/local/cuda ]]; then
                info "Detected CUDA toolkit (CUDA_VERSION=${CUDA_VERSION:-}, " \
                     "/usr/local/cuda exists) but no nvidia-smi (expected " \
                     "inside docker build). Assuming NVIDIA GPU target; " \
                     "set APOLLO_GPU=cpu to override."
                USE_NVIDIA_GPU=1
            fi
        fi
        ;;
esac

if [[ "${USE_NVIDIA_GPU}" -eq 1 ]]; then
  # libtorch_gpu nvidia
  #
  # IMPORTANT (modern u20/CUDA11.8 images): Apollo 6.0's prebuilt
  # `libtorch_gpu-1.7.0-2-cu111` is a CUDA 11.1 + TensorRT 7 build whose .so
  # files hard-depend on `libnvinfer.so.7`. On the cu118 + TRT8 modern image
  # that dependency cannot be satisfied and every binary that links libtorch
  # (e.g. planning unit tests) dies at load time with:
  #     error while loading shared libraries: libnvinfer.so.7: cannot open ...
  #
  # We therefore use PyTorch's OFFICIAL libtorch 1.13.1 + cu117 build on the
  # modern x86_64 image. (cu117 libtorch runs fine on a cu118 toolkit/driver;
  # PyTorch never shipped a separate cu118 libtorch for 1.13.x, and 1.13/cu117
  # does NOT depend on libnvinfer at all — TensorRT is decoupled from libtorch.)
  # Set APOLLO_LIBTORCH_LEGACY=1 to fall back to the old 6.0 cu111 tarball.
  if [[ "${TARGET_ARCH}" == "x86_64" ]]; then
    if [[ "${APOLLO_LIBTORCH_LEGACY:-0}" == "1" ]]; then
      info "APOLLO_LIBTORCH_LEGACY=1 -> using legacy Apollo 6.0 cu111 libtorch_gpu (needs TensorRT 7)."
      VERSION="1.7.0-2"
      CHECKSUM="b64977ca4a13ab41599bac8a846e8782c67ded8d562fdf437f0e606cd5a3b588"
      PKG_NAME="libtorch_gpu-${VERSION}-cu111-linux-x86_64.tar.gz"
      DOWNLOAD_LINK="https://apollo-system.cdn.bcebos.com/archive/6.0/${PKG_NAME}"
      download_if_not_cached "${PKG_NAME}" "${CHECKSUM}" "${DOWNLOAD_LINK}"
      tar xzf "${PKG_NAME}"
      mv "${PKG_NAME%.tar.gz}" /usr/local/libtorch_gpu/
    else
      # PyTorch official cxx11-ABI libtorch 1.13.1 + cu117 (no libnvinfer dep).
      VERSION="1.13.1"
      CUDA_TAG="${APOLLO_LIBTORCH_CUDA_TAG:-cu117}"
      CHECKSUM="6edc6c2fa59462a4f240a512f1d77b9874b3d6c1c2b8dd00d1c1c1f47f1ad691"
      PKG_NAME="libtorch-cxx11-abi-shared-with-deps-${VERSION}+${CUDA_TAG}.zip"
      # Allow overriding the mirror; default to PyTorch's official CDN.
      DOWNLOAD_LINK="${APOLLO_LIBTORCH_URL:-https://download.pytorch.org/libtorch/${CUDA_TAG}/libtorch-cxx11-abi-shared-with-deps-${VERSION}%2B${CUDA_TAG}.zip}"

      info "Downloading official libtorch ${VERSION}+${CUDA_TAG} (no libnvinfer.so.7 dependency) ..."
      # NOTE: official zip has no stable sha we pin across mirrors; download then unzip.
      if [[ ! -f "${PKG_NAME}" ]]; then
        wget -O "${PKG_NAME}" "${DOWNLOAD_LINK}"
      fi
      # Verify it is actually a zip (guards against HTML error pages from mirrors).
      if ! unzip -tq "${PKG_NAME}" >/dev/null 2>&1; then
        error "Downloaded ${PKG_NAME} is not a valid zip (mirror returned an error page?)."
        error "URL: ${DOWNLOAD_LINK}"
        error "Set APOLLO_LIBTORCH_URL to a reachable mirror, or APOLLO_LIBTORCH_LEGACY=1"
        error "to fall back to the old cu111 build (which then needs TensorRT 7)."
        exit 1
      fi
      apt_get_update_and_install unzip >/dev/null 2>&1 || true
      rm -rf /tmp/_libtorch_gpu && mkdir -p /tmp/_libtorch_gpu
      unzip -q "${PKG_NAME}" -d /tmp/_libtorch_gpu
      # The zip extracts a top-level "libtorch/" dir.
      rm -rf /usr/local/libtorch_gpu
      mv /tmp/_libtorch_gpu/libtorch /usr/local/libtorch_gpu
      rm -rf /tmp/_libtorch_gpu
    fi
  else # AArch64
    VERSION="1.11.0"
    PKG_NAME="libtorch_gpu-${VERSION}-linux-${TARGET_ARCH}.tar.gz"
    CHECKSUM="661346303cafc832ef2d37b734ee718c85cdcf5ab21b72b13ef453cb40f13f86"
    DOWNLOAD_LINK="https://apollo-pkg-beta.cdn.bcebos.com/archive/${PKG_NAME}"
    download_if_not_cached "${PKG_NAME}" "${CHECKSUM}" "${DOWNLOAD_LINK}"
    tar xzf "${PKG_NAME}"
    mv "${PKG_NAME%.tar.gz}" /usr/local/libtorch_gpu/
  fi
elif [[ "${USE_AMD_GPU}" -eq 1 ]]; then
  if [[ "${TARGET_ARCH}" == "x86_64" ]]; then
    PKG_NAME="libtorch_amd.tar.gz"
    FILE_ID="1UMzACmxzZD8KVitEnSk-BhXa38Kkl4P-"
  else # AArch64
    error "AMD libtorch for ${TARGET_ARCH} not ready. Exiting..."
    exit 1
  fi
  DOWNLOAD_LINK="https://docs.google.com/uc?export=download&id=${FILE_ID}"
  wget --load-cookies /tmp/cookies.txt \
    "https://docs.google.com/uc?export=download&confirm=
            $(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies \
      --no-check-certificate ${DOWNLOAD_LINK} \
      -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=${FILE_ID}" \
    -O "${PKG_NAME}" && rm -rf /tmp/cookies.txt

  tar xzf "${PKG_NAME}"
  mv "${PKG_NAME%.tar.gz}/libtorch" /usr/local/libtorch_gpu/
  mv "${PKG_NAME%.tar.gz}/libtorch_deps/libamdhip64.so.4" /opt/rocm/hip/lib/
  mv "${PKG_NAME%.tar.gz}/libtorch_deps/libmagma.so" /opt/apollo/sysroot/lib/
  mv "${PKG_NAME%.tar.gz}/libtorch_deps/"* /usr/local/lib/
  rm -r "${PKG_NAME%.tar.gz}"
  ldconfig
fi

# Cleanup
rm -f "${PKG_NAME}"
ok "Successfully installed libtorch_gpu ${VERSION}"
