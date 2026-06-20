# Apollo dev image for Ubuntu 20.04 + Python 3.10 + CUDA 11.8.
# Built on top of the matching cyber.x86_64.u20.nvidia image.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG GEOLOC=cn
ARG CLEAN_DEPS=yes
ARG APOLLO_DIST=stable
ARG INSTALL_MODE=build

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TZ=Asia/Shanghai

ENV http_proxy="http://127.0.0.1:7897"
ENV https_proxy="http://127.0.0.1:7897"

COPY installers /opt/apollo/installers
COPY rcfiles  /opt/apollo/rcfiles

RUN sed -i 's/^stage=.*/stage=dev/g' /etc/apollo.conf || \
    echo "stage=dev" >> /etc/apollo.conf

# 1) geo adjustment (apt + pip mirrors). Idempotent.
RUN bash /opt/apollo/installers/install_geo_adjustment.sh ${GEOLOC} || true

# 2) Apollo modules dependencies.
RUN bash /opt/apollo/installers/install_modules_base.sh
RUN bash /opt/apollo/installers/install_ordinary_modules.sh ${INSTALL_MODE}
RUN bash /opt/apollo/installers/install_drivers_deps.sh    ${INSTALL_MODE}
RUN bash /opt/apollo/installers/install_dreamview_deps.sh  ${GEOLOC}
RUN bash /opt/apollo/installers/install_contrib_deps.sh    ${INSTALL_MODE}
# Qt5 for modules/tools/visualizer (@qt -> /usr/local/qt5). The legacy
# install_qt.sh uses the removed Qt online .run installer; install_qt_modern.sh
# uses apt + symlinks instead. See README_modern.md Q17.
RUN bash /opt/apollo/installers/install_qt_modern.sh
# OpenNI runtime for Apollo's prebuilt PCL: /opt/apollo/sysroot/lib/libpcl_io.so
# is linked against libOpenNI.so.0 (xn* symbols). install_pcl.sh early-exits
# when it detects the prebuilt PCL and therefore never apt-installs OpenNI, so
# perception link fails with "libOpenNI.so.0 not found / undefined reference to
# xn*". Install it explicitly. See README_modern.md Q18.
# Only libopenni0 (provides libOpenNI.so.0 + the xn* symbols) is needed for the
# link; the sensor plugins (libopenni-sensor-pointclouds0 /
# libopenni-sensor-primesense0) Conflict with each other and are only required
# at runtime when actually talking to a Kinect/PrimeSense device, which the
# build/link does not. So we deliberately install just libopenni0 + headers.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libopenni0 libopenni-dev && \
    ldconfig && \
    rm -rf /var/lib/apt/lists/*
# ffmpeg: use the distro's apt ffmpeg (focal 4.2 / jammy 4.4) instead of
# Apollo's prebuilt bionic sysroot copy. @ffmpeg (third_party/ffmpeg) now points
# at /usr/include/x86_64-linux-gnu + /usr/lib/x86_64-linux-gnu, which link the
# distro's own libx264.so.163 / libx265.so.199 — no bionic .so.155/.so.179 shim
# needed. See README_modern.md Q19.
#
# (If you ever revert @ffmpeg back to the sysroot copy, install the legacy
#  codec shims instead with: bash /opt/apollo/installers/install_ffmpeg_compat.sh)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libavcodec-dev libavformat-dev libswscale-dev libavutil-dev \
        libavdevice-dev libavfilter-dev libswresample-dev && \
    ldconfig && \
    rm -rf /var/lib/apt/lists/*
# Seyond (Innovusion) lidar client SDK so modules/drivers/lidar/seyond compiles.
# apollo_package() pulls seyond into //modules/drivers/lidar:install_src via
# native.subpackages, so it cannot be excluded — the SDK must be present.
# Installs headers to /opt/apollo/sysroot/include/seyond + libinnoclientsdk to
# /opt/apollo/sysroot/lib. See README_modern.md Q20. Set SKIP_SEYOND_SDK=1 only
# if you also remove the seyond package from the source tree.
RUN bash /opt/apollo/installers/install_seyond_sdk.sh
RUN bash /opt/apollo/installers/install_gpu_support.sh
RUN bash /opt/apollo/installers/install_release_deps.sh

RUN bash /opt/apollo/installers/post_install.sh dev
RUN bash /opt/apollo/installers/install_pkg_repo.sh

COPY rcfiles/setup.sh /opt/apollo/neo/

# 3) Optional sensor drivers (best-effort).
RUN bash /opt/apollo/installers/install_rsdriver.sh
RUN bash /opt/apollo/installers/install_livox_driver.sh
RUN bash /opt/apollo/installers/install_hesai2_driver.sh
RUN bash /opt/apollo/installers/install_vanjee_driver.sh

# 4) Python ML deps (TensorFlow) — installed into an *isolated venv* to
#    avoid contaminating the system python's pinned dependency set.
#
#    Background:
#      - The cyber stage pins `protobuf>=5.26,<6` (required by grpcio-tools
#        1.70 and by Apollo's protobuf 5.x C++ runtime / Python bindings).
#      - TensorFlow <= 2.17 hard-requires `protobuf<5` (it ships its own
#        4.x C extension); 2.18 supports protobuf>=5 but bumps to CUDA 12.
#      - On CUDA 11.8 (this u20 image), the latest line that still has an
#        official prebuilt wheel is the 2.15.x series. To make it coexist
#        with the system protobuf 5.x, we put TF in its own venv at
#        /opt/apollo/venv/tf and expose a helper script for activation.
#
#    Inside that venv, pip is free to pick whatever protobuf/numpy/etc.
#    versions TF wants — none of it leaks back to the system python that
#    Apollo's bazel build relies on.
#
#    NOTE on the PyPI mirror choice for TensorFlow:
#      Tsinghua's mirror (pypi.tuna.tsinghua.edu.cn) does NOT mirror the
#      tensorflow series past 2.13.x — it returns "Could not find a version
#      that satisfies the requirement tensorflow==2.15.*". So we MUST fall
#      back to a mirror (or origin) that has the full tensorflow index.
#      We try, in order:
#         1) aliyun pypi mirror   (CN, fast, generally has full tensorflow index)
#         2) douban pypi mirror   (CN, secondary)
#         3) pypi.org             (origin; uses the http_proxy set above)
#      Each candidate is tried with `pip install` — the first one that
#      finds tensorflow==2.15.* wins. The system pip default mirror
#      (Tsinghua, set by install_geo_adjustment.sh in the cyber stage) is
#      explicitly bypassed by always passing `-i ...`.
# Use bash explicitly: the `_try_install` helper below uses `local`, which
# the default Dockerfile shell (/bin/sh -> dash) does not support.
# SHELL ["/bin/bash", "-c"]
# RUN set -e; \
#     python3 -m pip install --no-cache-dir --upgrade virtualenv && \
#     python3 -m virtualenv -p python3 /opt/apollo/venv/tf && \
#     /opt/apollo/venv/tf/bin/pip install --no-cache-dir --upgrade pip && \
#     TF_PIN="tensorflow==2.15.*"; \
#     _try_install() { \
#         local _idx="$1"; local _host; \
#         _host="$(echo "${_idx}" | awk -F/ '{print $3}')"; \
#         echo "[INFO] trying tensorflow from ${_idx}"; \
#         /opt/apollo/venv/tf/bin/pip install --no-cache-dir \
#             -i "${_idx}" --trusted-host "${_host}" \
#             "${TF_PIN}"; \
#     }; \
#     _try_install "https://mirrors.aliyun.com/pypi/simple/"   || \
#     _try_install "https://pypi.douban.com/simple/"           || \
#     _try_install "https://pypi.org/simple/"                  || \
#     { echo "[ERROR] all pypi mirrors failed for ${TF_PIN}"; exit 1; }; \
#     printf '%s\n' \
#         '#!/usr/bin/env bash' \
#         '# Source this file (or run "activate_tf") to get a python with TensorFlow 2.15.' \
#         '# Do NOT activate it before running bazel — bazel needs the system python.' \
#         'export TF_VENV=/opt/apollo/venv/tf' \
#         'alias activate_tf="source ${TF_VENV}/bin/activate"' \
#         > /etc/profile.d/apollo_tf_venv.sh && \
#     chmod +x /etc/profile.d/apollo_tf_venv.sh
# SHELL ["/bin/sh", "-c"]

ENV http_proxy=""
ENV https_proxy=""

WORKDIR /apollo