#!/usr/bin/env bash

###############################################################################
# Copyright 2024 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# Minimal environment installer for Ubuntu 22.04 (jammy) + Python 3.10
###############################################################################

# Fail on first error.
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"
. ./installer_base.sh

MY_GEO=$1; shift || true
ARCH="$(uname -m)"

##----------------------------##
##  APT sources.list settings |
##----------------------------##

if [[ "${ARCH}" == "x86_64" ]]; then
    if [[ "${MY_GEO}" == "cn" ]]; then
        if [[ -f "${RCFILES_DIR}/sources.list.cn.x86_64.u22" ]]; then
            cp -f "${RCFILES_DIR}/sources.list.cn.x86_64.u22" /etc/apt/sources.list
        else
            # Fallback: rewrite default sources.list to aliyun
            sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list || true
            sed -i 's@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list || true
        fi
    fi
else
    if [[ "${MY_GEO}" == "cn" ]]; then
        # aarch64 jammy: use ubuntu-ports mirror
        cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.aliyun.com/ubuntu-ports/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ jammy-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ jammy-security main restricted universe multiverse
EOF
    fi
fi

# Some NVIDIA base images ship a cuda.list / nvidia-ml.list that may be slow
# in CN; rewrite to aliyun cuda mirror if accessible.
if [[ "${MY_GEO}" == "cn" ]]; then
    for f in /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/nvidia-ml.list; do
        [[ -f "$f" ]] || continue
        sed -i 's@developer.download.nvidia.com@mirrors.aliyun.com/nvidia-cuda@g' "$f" || true
    done
fi

apt-get -y update

# Core utilities (note: python3-distutils is not needed in 22.04;
# python3.10 is the default; use universe `python-is-python3` to wire `python`).
apt_get_update_and_install \
    apt-utils \
    bc \
    ca-certificates \
    curl \
    file \
    gawk \
    git \
    gnupg \
    less \
    locales \
    lsb-release \
    lsof \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    python-is-python3 \
    sed \
    software-properties-common \
    sudo \
    tzdata \
    unzip \
    vim \
    wget \
    zip \
    xz-utils

if [[ "${ARCH}" == "aarch64" ]]; then
    apt-get -y install kmod
fi

# Build tooling. Ubuntu 22.04 default toolchain is gcc/g++-11. We keep gcc-11
# as primary (Apollo bazel build supports newer toolchains here). If a project
# explicitly needs gcc-9, install in addition.
MY_STAGE=
if [[ -f /etc/apollo.conf ]]; then
    MY_STAGE="$(awk -F '=' '/^stage=/ {print $2}' /etc/apollo.conf 2>/dev/null)"
fi

if [[ "${MY_STAGE}" != "runtime" ]]; then
    apt_get_update_and_install \
        build-essential \
        autoconf \
        automake \
        gcc-11 \
        g++-11 \
        gdb \
        libtool \
        patch \
        pkg-config \
        libexpat1-dev \
        linux-libc-dev

    # Make gcc-11 the default
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-11 || true
fi

##----------------##
##    SUDO        ##
##----------------##
sed -i /etc/sudoers -re 's/^%sudo.*/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g'

##----------------##
## default shell  ##
##----------------##
chsh -s /bin/bash
ln -sf /bin/bash /bin/sh

##----------------##
## Locale & TZ    ##
##----------------##
locale-gen en_US.UTF-8 || true
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || true
echo "Asia/Shanghai" > /etc/timezone || true

##----------------##
## Python Setings |
##----------------##
# python-is-python3 already symlinks /usr/bin/python -> python3 (3.10).
# Keep an update-alternatives entry as well for compatibility with 18.04 logic.
update-alternatives --install /usr/bin/python python /usr/bin/python3 36 || true

if [[ "${MY_GEO}" == "cn" ]]; then
    PYPI_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
    python3 -m pip install --no-cache-dir --break-system-packages \
        --timeout 30 -i "${PYPI_MIRROR}" -U pip || \
        python3 -m pip install --no-cache-dir --timeout 30 -i "${PYPI_MIRROR}" -U pip
    python3 -m pip config set global.index-url "${PYPI_MIRROR}"
else
    python3 -m pip install --no-cache-dir --timeout 30 -U pip || true
fi

python3 -m pip install --no-cache-dir -U setuptools wheel

# Clean up cache to reduce layer size.
apt-get clean && \
    rm -rf /var/lib/apt/lists/*