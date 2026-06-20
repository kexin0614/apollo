#!/usr/bin/env bash

###############################################################################
# CyberRT dependency installer for "modern" base OS (Ubuntu 20.04 / 22.04)
# where glibc is already >= 2.31. We reuse upstream sub-installers but skip
# the trailing libc6-2.31-ubuntu18 patch step, which is only meaningful for
# the original 18.04 image.
###############################################################################
set -e

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "${CURR_DIR}/installer_base.sh"

INSTALL_MODE="${1:-build}"

apt-get -y update && \
    apt-get -y install --no-install-recommends \
        ncurses-dev \
        libuuid1 \
        uuid-dev \
        libssl-dev \
        zlib1g-dev

info "Install protobuf ..."
bash "${CURR_DIR}/install_protobuf.sh" "${INSTALL_MODE}"

info "Install fast-rtps ..."
# NOTE: upstream eProsima/Fast-RTPS has been renamed to Fast-DDS and the
# branch `release/1.5.0` no longer exists, which makes
# `install_fast-rtps.sh build` fail with "Remote branch release/1.5.0 not
# found in upstream origin". Apollo's cyber framework still ABI-depends on
# the 1.5.0 binaries published on Apollo's CDN, so on focal/jammy we
# *always* use the prebuilt tarball regardless of ${INSTALL_MODE}. The
# tarball is a static install rooted at /usr/local/fast-rtps and works
# fine against glibc 2.31 / 2.35.
bash "${CURR_DIR}/install_fast-rtps.sh" download

info "Install abseil ..."
bash "${CURR_DIR}/install_abseil.sh" "${INSTALL_MODE}"

info "Install gflags & glog ..."
bash "${CURR_DIR}/install_gflags_glog.sh" "${INSTALL_MODE}"

# bvar (`third_party/var/bvar/...`) — see comments inside install_bvar.sh.
# Apollo's bionic deb is grabbed directly because focal/jammy codenames have
# no `bvar` published. Without this, cyber/statistics + transmitter code
# fails to compile with `fatal error: third_party/var/bvar/bvar.h`.
info "Install bvar (from Apollo bionic deb, codename-agnostic) ..."
bash "${CURR_DIR}/install_bvar.sh"

# tinyxml2 + asio — REQUIRED by cyber/plugin_manager (and later by perception
# plugins). The original Apollo flow only adds these inside dev image via
# install_ordinary_modules.sh / install_dreamview_deps.sh, but `cyber/...`
# itself already #include <tinyxml2.h>, so we must keep them in the cyber
# layer. Note: install_fast-rtps.sh may strip libtinyxml2-dev at the end if
# CLEAN_DEPS is set (e.g. for INSTALL_MODE=download); we re-install here
# unconditionally to make this layer self-contained.
info "Install tinyxml2 / asio dev headers (required by cyber/plugin_manager) ..."
apt-get -y update && \
    apt-get -y install --no-install-recommends \
        libasio-dev \
        libtinyxml2-dev

apt-get clean && \
    rm -rf /var/lib/apt/lists/*

info "Skip libc6 patch (host glibc already >= 2.28)."
