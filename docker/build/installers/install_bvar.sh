#!/usr/bin/env bash
###############################################################################
# Install Apollo's prebuilt `bvar` headers + library (the `third_party/var/`
# tree referenced by cyber/statistics, cyber/transport, etc.).
#
# Why this script exists
# ----------------------
# Apollo provides `bvar` as a deb package on its own apt repo
# (`https://apollo-pkg-beta.cdn.bcebos.com/apollo/core`). On Ubuntu 18.04
# (bionic) it is pulled in by `install_pkg_repo.sh` via `apt install bvar`.
# That repo, however, ONLY publishes the `bvar` deb under the `bionic`
# codename — not under `focal` or `jammy`. So on our 20.04/22.04 modern
# image, `apt install bvar` silently fails (the original line is suffixed
# with `|| true`), and any cyber TU that includes `third_party/var/bvar/...`
# fails to compile with:
#
#     fatal error: third_party/var/bvar/bvar.h: No such file or directory
#
# This script bypasses apt entirely: it grabs the bionic .deb directly,
# extracts it under /, and installs the headers to
#   /usr/local/include/third_party/var/...
# and the shared library `libbvar.so` to /usr/local/lib/. That layout is
# exactly what cyber's BUILD files (`linkopts = ["-lbvar"]`) and source
# files (`#include "third_party/var/bvar/bvar.h"`) expect.
#
# The deb depends only on `libc6`, so on focal (glibc 2.31) and jammy
# (glibc 2.35) it works without rebuilds — there is no C++ ABI issue
# because cyber itself links against the same `libstdc++` ABI used by the
# .deb (the dual-ABI `_GLIBCXX_USE_CXX11_ABI=1` default).
###############################################################################
set -e

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "${CURR_DIR}/installer_base.sh"

# Allow override; default = the version Apollo's bionic repo currently ships.
BVAR_DEB_URL="${BVAR_DEB_URL:-https://apollo-pkg-beta.cdn.bcebos.com/apollo/core/pool/main/b/bvar/bvar_9.0.0-rc1-r1_amd64.deb}"
BVAR_DEB_SHA256="${BVAR_DEB_SHA256:-495d26ca3a272c4b368ee2632a757070e3dfcb0ff6dd5866a2025974f9cc6f66}"

ARCH="$(uname -m)"
if [[ "${ARCH}" != "x86_64" ]]; then
    warning "install_bvar.sh: arch ${ARCH} not supported by Apollo's prebuilt bvar deb; skipping."
    exit 0
fi

# Already installed?
if [[ -f /usr/local/include/third_party/var/bvar/bvar.h ]] && \
   ldconfig -p | grep -q "libbvar.so"; then
    info "bvar already installed; skipping."
    exit 0
fi

PKG="bvar_apollo.deb"
download_if_not_cached "${PKG}" "${BVAR_DEB_SHA256}" "${BVAR_DEB_URL}"

# `dpkg -i` would normally also run maintainer scripts and add it to dpkg's
# database, but we only need the file payload. `dpkg-deb -x` extracts the
# data archive into the target directory without registering the package,
# avoiding any "Depends:" pickiness.
dpkg-deb -x "${PKG}" /

ldconfig
rm -f "${PKG}"

# Sanity check.
if [[ ! -f /usr/local/include/third_party/var/bvar/bvar.h ]]; then
    error "install_bvar.sh: header /usr/local/include/third_party/var/bvar/bvar.h missing after extract"
    exit 1
fi
if ! ldconfig -p | grep -q "libbvar.so"; then
    warning "install_bvar.sh: libbvar.so not found by ldconfig; cyber link step (-lbvar) will fail."
    warning "Files extracted from the .deb:"
    dpkg-deb -c "${PKG}" 2>/dev/null | grep -E "\.so|\.a" || true
fi

info "Done installing bvar headers + libs from Apollo's bionic deb."