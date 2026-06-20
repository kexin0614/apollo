#!/usr/bin/env bash

###############################################################################
# Copyright 2024 The Apollo Authors. All Rights Reserved.
#
# Minimal-environment installer for Ubuntu 20.04 (focal).
#
# Difference vs. the original install_minimal_environment.sh (which targets
# 18.04 + python3.6):
#   - default APT mirror -> aliyun (when GEOLOC=cn);
#   - install python3.10 from deadsnakes PPA and make it the default `python3`
#     and `python` (also re-create /usr/bin/pip3 -> python3.10 -m pip);
#   - keep gcc-9 (the 20.04 default) so the toolchain matches CUDA 11.8 ABI.
###############################################################################

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"
. ./installer_base.sh

MY_GEO="${1:-}"
ARCH="$(uname -m)"

##----------------------------##
##  APT sources.list settings |
##----------------------------##

if [[ "${ARCH}" == "x86_64" ]]; then
    if [[ "${MY_GEO}" == "cn" ]]; then
        if [[ -f "${RCFILES_DIR}/sources.list.cn.x86_64.u20" ]]; then
            cp -f "${RCFILES_DIR}/sources.list.cn.x86_64.u20" /etc/apt/sources.list
        else
            sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list || true
            sed -i 's@//security.ubuntu.com@//mirrors.aliyun.com@g'  /etc/apt/sources.list || true
        fi
    fi
else
    if [[ "${MY_GEO}" == "cn" ]]; then
        cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.aliyun.com/ubuntu-ports/ focal main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ focal-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ focal-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-ports/ focal-security main restricted universe multiverse
EOF
    fi
fi

apt-get -y update

##-----------------------------##
##  Core utilities             ##
##-----------------------------##
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

##-----------------------------##
##  Build tooling              ##
##-----------------------------##
MY_STAGE=
if [[ -f /etc/apollo.conf ]]; then
    MY_STAGE="$(awk -F '=' '/^stage=/ {print $2}' /etc/apollo.conf 2>/dev/null)"
fi

if [[ "${MY_STAGE}" != "runtime" ]]; then
    apt_get_update_and_install \
        build-essential \
        autoconf \
        automake \
        gcc-9 \
        g++-9 \
        gdb \
        libtool \
        patch \
        pkg-config \
        libexpat1-dev \
        linux-libc-dev

    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-9 || true
fi

##-----------------------------##
##  Python 3.10 (deadsnakes)   ##
##-----------------------------##
# We *try* to install python3.10 from the deadsnakes PPA so that downstream
# Apollo code can use the modern interpreter. If the PPA cannot be reached
# (key fetch fails, mirror unreachable, etc.) we **fall back to the system
# python3.8** that ships with focal — Apollo's cyber/dreamview will still
# build, but you won't get 3.10 features. Set FORCE_PY310=1 to make a failed
# 3.10 install fatal instead of a warning.
FORCE_PY310="${FORCE_PY310:-0}"
PY310_OK=0

# always install the system python3.8 toolchain first, so that we have a
# guaranteed working interpreter regardless of how the deadsnakes step ends.
apt_get_update_and_install \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-distutils

if [[ "${ARCH}" == "x86_64" ]]; then
    # ---- Step 1: install deadsnakes PPA signing key ----
    # `add-apt-repository -y ppa:deadsnakes/ppa` uses HKP on port 11371 to
    # fetch the key from keyserver.ubuntu.com, which is often RSTed by GFW.
    # We download the ASCII-armored key over HTTPS instead. Multiple mirrors
    # are tried.
    #
    # The deadsnakes PPA signing key fingerprint is:
    #   F23C5A6CF475977595C89F51BA6932366A755776
    # (published at https://launchpad.net/~deadsnakes)
    DEADSNAKES_FP="F23C5A6CF475977595C89F51BA6932366A755776"
    install -d -m 0755 /etc/apt/keyrings
    KEYRING="/etc/apt/keyrings/deadsnakes.gpg"

    DEADSNAKES_KEY_URLS=(
        # HKP-over-HTTPS (port 443) on keyserver.ubuntu.com — usually OK in CN.
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${DEADSNAKES_FP}"
        # openpgp.org HTTPS
        "https://keys.openpgp.org/vks/v1/by-fingerprint/${DEADSNAKES_FP}"
    )

    fetched=0
    for url in "${DEADSNAKES_KEY_URLS[@]}"; do
        info "Fetching deadsnakes signing key: ${url}"
        if curl -fsSL --connect-timeout 15 --max-time 60 \
                -o /tmp/deadsnakes.asc "${url}"; then
            if gpg --no-default-keyring --keyring "${KEYRING}" \
                   --import /tmp/deadsnakes.asc 2>/dev/null; then
                fetched=1
                rm -f /tmp/deadsnakes.asc
                break
            else
                warning "Imported failed for ${url}; trying next."
            fi
        else
            warning "Download failed for ${url}; trying next."
        fi
        rm -f /tmp/deadsnakes.asc
    done

    if [[ "${fetched}" -ne 1 ]]; then
        warning "All HTTPS key endpoints failed; falling back to gpg --recv-keys."
        for ks in \
            "hkps://keyserver.ubuntu.com:443" \
            "hkps://keys.openpgp.org" \
            "hkp://pgp.mit.edu:80"; do
            info "Trying keyserver: ${ks}"
            if gpg --no-default-keyring --keyring "${KEYRING}" \
                   --keyserver "${ks}" --recv-keys "${DEADSNAKES_FP}"; then
                fetched=1
                break
            fi
        done
    fi

    if [[ "${fetched}" -ne 1 ]]; then
        warning "Failed to fetch deadsnakes signing key from every mirror."
        warning "Skipping python3.10 install; will keep system python3.8."
        warning "(If you really need 3.10, pre-populate the key manually:"
        warning "   curl -fsSL https://<your-mirror>/deadsnakes.asc \\"
        warning "        | gpg --no-default-keyring --keyring ${KEYRING} --import"
        warning " then re-run this script, or set FORCE_PY310=1 to abort.)"
        if [[ "${FORCE_PY310}" == "1" ]]; then
            error "FORCE_PY310=1 set; aborting."
            exit 1
        fi
        PY310_OK=0
    else
        chmod 0644 "${KEYRING}"
        PY310_OK=1
    fi

    # ---- Step 2: register the apt source (only if we got a key) ----
    if [[ "${PY310_OK}" == "1" ]]; then
        DEADSNAKES_LINE_USTC="deb [signed-by=${KEYRING}] https://launchpad.proxy.ustclug.org/deadsnakes/ppa/ubuntu focal main"
        DEADSNAKES_LINE_LP="deb [signed-by=${KEYRING}] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu focal main"

        if [[ "${MY_GEO}" == "cn" ]]; then
            echo "${DEADSNAKES_LINE_USTC}" > /etc/apt/sources.list.d/deadsnakes.list
        else
            echo "${DEADSNAKES_LINE_LP}"   > /etc/apt/sources.list.d/deadsnakes.list
        fi

        if ! apt-get -y update; then
            warning "apt-get update failed with current deadsnakes mirror; switching."
            if [[ "${MY_GEO}" == "cn" ]]; then
                echo "${DEADSNAKES_LINE_LP}"   > /etc/apt/sources.list.d/deadsnakes.list
            else
                echo "${DEADSNAKES_LINE_USTC}" > /etc/apt/sources.list.d/deadsnakes.list
            fi
            if ! apt-get -y update; then
                warning "Both deadsnakes mirrors failed; falling back to py3.8."
                rm -f /etc/apt/sources.list.d/deadsnakes.list
                apt-get -y update || true
                PY310_OK=0
            fi
        fi
    fi

    # Sanity check: make sure apt actually sees a python3.10 candidate.
    if [[ "${PY310_OK}" == "1" ]] && \
       ! apt-cache policy python3.10 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        warning "deadsnakes PPA did not expose python3.10; falling back to py3.8."
        cat /etc/apt/sources.list.d/deadsnakes.list 2>/dev/null || true
        PY310_OK=0
    fi

    if [[ "${PY310_OK}" == "1" ]]; then
        # Try to install the full python3.10 toolchain. python3.10-dev is
        # required for any C-extension build; if it's missing we treat the
        # whole 3.10 install as failed and roll back to py3.8.
        if apt-get -y install \
                python3.10 \
                python3.10-dev \
                python3.10-venv \
                python3.10-distutils; then
            update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 100
            update-alternatives --install /usr/bin/python  python  /usr/bin/python3.10 100
            update-alternatives --set     python3 /usr/bin/python3.10
            update-alternatives --set     python  /usr/bin/python3.10

            # Bootstrap pip for python3.10 (system pip is bound to py3.8).
            curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
            if [[ "${MY_GEO}" == "cn" ]]; then
                python3.10 /tmp/get-pip.py -i https://pypi.tuna.tsinghua.edu.cn/simple
            else
                python3.10 /tmp/get-pip.py
            fi
            rm -f /tmp/get-pip.py
            ln -sf /usr/local/bin/pip /usr/local/bin/pip3 || true
            ok "python3.10 installed and set as default."
        else
            warning "apt failed to install python3.10 toolchain; falling back to py3.8."
            PY310_OK=0
        fi
    fi

    if [[ "${PY310_OK}" != "1" ]]; then
        if [[ "${FORCE_PY310}" == "1" ]]; then
            error "FORCE_PY310=1 set but python3.10 install failed."
            exit 1
        fi
        warning "Continuing with system python3.8. Apollo will build with 3.8;"
        warning "if you later want 3.10, fix the deadsnakes key/mirror and re-run this script."
        update-alternatives --install /usr/bin/python python /usr/bin/python3 36 || true
    fi
else
    # AArch64: deadsnakes only ships x86_64; just keep system python3.8.
    update-alternatives --install /usr/bin/python python /usr/bin/python3 36 || true
fi

##-----------------------------##
##  SUDO / shell / locale / TZ ##
##-----------------------------##
sed -i /etc/sudoers -re 's/^%sudo.*/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g'
chsh -s /bin/bash
ln -sf /bin/bash /bin/sh
locale-gen en_US.UTF-8 || true
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || true
echo "Asia/Shanghai" > /etc/timezone || true

##-----------------------------##
##  PIP mirror                 ##
##-----------------------------##
if [[ "${MY_GEO}" == "cn" ]]; then
    PYPI_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
    python3 -m pip install --no-cache-dir --timeout 30 -i "${PYPI_MIRROR}" -U pip || true
    python3 -m pip config set global.index-url "${PYPI_MIRROR}"
fi
python3 -m pip install --no-cache-dir -U setuptools wheel

# Clean up cache to reduce layer size.
apt-get clean && \
    rm -rf /var/lib/apt/lists/*
