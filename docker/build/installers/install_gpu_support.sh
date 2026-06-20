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

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. ${CURR_DIR}/installer_base.sh

apt_get_update_and_install \
    libopenblas-dev \
    libatlas-base-dev \
    liblapack-dev

# Note(infra): build magma before mkl
info "Install Magma ..."
bash ${CURR_DIR}/install_magma.sh

info "Install libtorch ..."
bash ${CURR_DIR}/install_libtorch.sh

# TensorRT: required by ./apollo.sh config in the dev stage (bootstrap.py forces
# TF_NEED_TENSORRT=1 when stage=dev && TF_NEED_CUDA=1). The CUDA base image does
# NOT ship TensorRT, so we install it explicitly here. See install_tensorrt.sh
# and README_modern.md Q16. Set SKIP_TENSORRT=1 for a CPU-only image.
info "Install TensorRT ..."
bash ${CURR_DIR}/install_tensorrt.sh

# openmpi @cuda
# pcl @cuda
# opencv @cuda

# Clean up cache to reduce layer size.
apt-get clean && \
    rm -rf /var/lib/apt/lists/*
