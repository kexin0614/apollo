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
# Install Qt5 for the modern (u20/u22) dev images, the apt way.
#
# Why this exists:
#   The legacy install_qt.sh uses cuteci + the Qt online installer
#   (qt-opensource-linux-x64-5.12.9.run). That .run installer has been removed
#   from Qt's servers, needs a Qt account / GUI interaction, and is unreliable
#   from China — so the modern dev image never installed Qt, and `./apollo.sh
#   build` fails fetching the @qt repository:
#
#     fetching new_local_repository rule //external:qt:
#       The repository's path is "/usr/local/qt5/include" but this directory
#       does not exist.
#
#   third_party/qt5/workspace.bzl points @qt at /usr/local/qt5/include, and
#   third_party/qt5/qt.BUILD links against /usr/local/qt5/lib with -lQt5Core,
#   -lQt5Widgets, -lQt5Gui, -lQt5OpenGL and includes the QtCore / QtWidgets /
#   QtGui / QtOpenGL header subdirs.
#
#   Ubuntu focal (20.04) ships Qt 5.12.8 and jammy (22.04) ships Qt 5.15.x via
#   apt. We install the -dev packages and then expose them under the
#   /usr/local/qt5/{include,lib} layout that Apollo's bazel rules expect, via
#   symlinks. No GUI, no account, fully offline-capable from the distro mirror.

set -e

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "${CURR_DIR}/installer_base.sh"

TARGET_ARCH="$(uname -m)"

QT5_PATH="/usr/local/qt5"

# Idempotency.
if [[ -d "${QT5_PATH}/include/QtCore" ]] && [[ -e "${QT5_PATH}/lib/libQt5Core.so" ]]; then
    ok "Qt5 already exposed at ${QT5_PATH}; nothing to do."
    exit 0
fi

info "Installing Qt5 (apt) for the modern dev image ..."

# Runtime + dev packages. qtbase5-dev pulls in QtCore/QtGui/QtWidgets;
# libqt5opengl5-dev provides QtOpenGL; the rest are the runtime libs Apollo's
# visualizer / dreamview tooling dlopen at runtime.
apt_get_update_and_install \
    qtbase5-dev \
    qtbase5-dev-tools \
    qt5-qmake \
    libqt5core5a \
    libqt5gui5 \
    libqt5widgets5 \
    libqt5opengl5 \
    libqt5opengl5-dev \
    libx11-xcb1 \
    libfreetype6 \
    libdbus-1-3 \
    libfontconfig1 \
    libxkbcommon0 \
    libxkbcommon-x11-0

# Locate the multiarch dirs apt used. On focal/jammy x86_64 these are:
#   headers -> /usr/include/x86_64-linux-gnu/qt5
#   libs    -> /usr/lib/x86_64-linux-gnu
GNU_TRIPLET="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
QT_INC_DIR=""
for d in \
    "/usr/include/${GNU_TRIPLET}/qt5" \
    "/usr/include/qt5" ; do
    if [[ -d "${d}/QtCore" ]]; then
        QT_INC_DIR="${d}"
        break
    fi
done
if [[ -z "${QT_INC_DIR}" ]]; then
    error "Could not find the Qt5 headers (QtCore) after apt install."
    error "Looked under /usr/include/${GNU_TRIPLET}/qt5 and /usr/include/qt5."
    exit 1
fi

QT_LIB_DIR=""
for d in \
    "/usr/lib/${GNU_TRIPLET}" \
    "/usr/lib" ; do
    if [[ -e "${d}/libQt5Core.so" ]] || ls "${d}"/libQt5Core.so* >/dev/null 2>&1; then
        QT_LIB_DIR="${d}"
        break
    fi
done
if [[ -z "${QT_LIB_DIR}" ]]; then
    error "Could not find libQt5Core.so after apt install."
    exit 1
fi

info "Qt5 headers : ${QT_INC_DIR}"
info "Qt5 libs    : ${QT_LIB_DIR}"

# Expose the apt-installed Qt5 under the /usr/local/qt5 layout Apollo expects.
#   /usr/local/qt5/include -> .../qt5   (so .../qt5/QtCore is reachable)
#   /usr/local/qt5/lib     -> the multiarch lib dir
#   /usr/local/qt5/bin     -> qmake etc. (best-effort)
rm -rf "${QT5_PATH}"
mkdir -p "${QT5_PATH}"
ln -sfn "${QT_INC_DIR}" "${QT5_PATH}/include"
ln -sfn "${QT_LIB_DIR}" "${QT5_PATH}/lib"

# qmake / moc / uic etc. live in a versioned dir on focal/jammy.
QT_BIN_DIR=""
for d in \
    "/usr/lib/${GNU_TRIPLET}/qt5/bin" \
    "/usr/lib/qt5/bin" ; do
    if [[ -d "${d}" ]]; then
        QT_BIN_DIR="${d}"
        break
    fi
done
if [[ -n "${QT_BIN_DIR}" ]]; then
    ln -sfn "${QT_BIN_DIR}" "${QT5_PATH}/bin"
fi

# Make the libs discoverable at runtime.
echo "${QT5_PATH}/lib" > /etc/ld.so.conf.d/qt.conf
ldconfig

# Export env for interactive shells (mirror legacy install_qt.sh behaviour).
if [[ -f "${APOLLO_PROFILE}" ]]; then
    __mytext="""
export QT5_PATH=\"${QT5_PATH}\"
export QT_QPA_PLATFORM_PLUGIN_PATH=\"${QT_LIB_DIR}/qt5/plugins\"
add_to_path \"\${QT5_PATH}/bin\"
"""
    echo "${__mytext}" | tee -a "${APOLLO_PROFILE}" >/dev/null
fi

# Sanity check the layout Apollo's bazel rules rely on.
[[ -d "${QT5_PATH}/include/QtCore" ]]    || { error "QtCore headers missing under ${QT5_PATH}/include"; exit 1; }
[[ -d "${QT5_PATH}/include/QtWidgets" ]] || warning "QtWidgets headers missing under ${QT5_PATH}/include"
[[ -d "${QT5_PATH}/include/QtGui" ]]     || warning "QtGui headers missing under ${QT5_PATH}/include"
[[ -d "${QT5_PATH}/include/QtOpenGL" ]]  || warning "QtOpenGL headers missing under ${QT5_PATH}/include"
ls "${QT5_PATH}/lib"/libQt5Core.so* >/dev/null 2>&1 || { error "libQt5Core.so missing under ${QT5_PATH}/lib"; exit 1; }

QT_VER="$(cat "${QT_INC_DIR}/QtCore/qglobal.h" 2>/dev/null | awk -F'"' '/QT_VERSION_STR/{print $2; exit}')"
ok "Successfully exposed Qt5 ${QT_VER:-?} at ${QT5_PATH} (include -> ${QT_INC_DIR}, lib -> ${QT_LIB_DIR})"