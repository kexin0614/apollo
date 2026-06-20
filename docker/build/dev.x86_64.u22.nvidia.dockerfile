# Apollo dev image for Ubuntu 22.04 + Python 3.10 + CUDA 12 (NVIDIA GPU)
#
# Build context: docker/build/
# Default BASE_IMAGE: a CyberRT image previously built from
#                     cyber.x86_64.u22.nvidia.dockerfile.
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

# Refresh installer scripts (rcfiles already shipped by cyber image, but we
# overwrite to make sure we have the latest u22-aware versions).
COPY installers /opt/apollo/installers
COPY rcfiles  /opt/apollo/rcfiles

# Switch /etc/apollo.conf to dev stage.
RUN sed -i 's/^stage=.*/stage=dev/g' /etc/apollo.conf || \
    echo "stage=dev" >> /etc/apollo.conf

# 1) geo adjustment (apt + pip mirrors). Safe to re-run.
RUN bash /opt/apollo/installers/install_geo_adjustment.sh ${GEOLOC} || true

# 2) modules base + ordinary modules + drivers + dreamview + contrib + gpu
#    Each step may pull dozens of system / pip packages; in CN we already
#    rewrote sources.list and pip index.
RUN bash /opt/apollo/installers/install_modules_base.sh
RUN bash /opt/apollo/installers/install_ordinary_modules.sh ${INSTALL_MODE}
RUN bash /opt/apollo/installers/install_drivers_deps.sh   ${INSTALL_MODE}
RUN bash /opt/apollo/installers/install_dreamview_deps.sh ${GEOLOC}
RUN bash /opt/apollo/installers/install_contrib_deps.sh   ${INSTALL_MODE}
RUN bash /opt/apollo/installers/install_gpu_support.sh    || true
RUN bash /opt/apollo/installers/install_release_deps.sh   || true

# 3) post install + pkg repo + setup script
RUN bash /opt/apollo/installers/post_install.sh dev || true
RUN bash /opt/apollo/installers/install_pkg_repo.sh || true

COPY rcfiles/setup.sh /opt/apollo/neo/

# 4) optional sensor drivers (best-effort; some upstream sources may be
#    unreachable from CN, so we don't fail the whole build on them).
RUN bash /opt/apollo/installers/install_rsdriver.sh      || true
RUN bash /opt/apollo/installers/install_livox_driver.sh  || true
RUN bash /opt/apollo/installers/install_hesai2_driver.sh || true
RUN bash /opt/apollo/installers/install_vanjee_driver.sh || true

# 5) Python ML deps (TensorFlow) — installed into an *isolated venv*.
#    See dev.x86_64.u20.nvidia.dockerfile for the full rationale; in short,
#    TF <= 2.17 requires `protobuf<5` while Apollo's cyber stage pins
#    `protobuf>=5.26`. Mixing them in the system python breaks both.
#    On u22 + CUDA 12, the latest TF line with prebuilt wheels is 2.16+;
#    we use 2.16.* which still supports protobuf<5 and Python 3.10.
#    Use `source /etc/profile.d/apollo_tf_venv.sh && activate_tf` to
#    enter the venv when you need TensorFlow.
RUN set -e; \
    python3 -m pip install --no-cache-dir --upgrade virtualenv && \
    python3 -m virtualenv -p python3 /opt/apollo/venv/tf && \
    /opt/apollo/venv/tf/bin/pip install --no-cache-dir --upgrade pip && \
    ( /opt/apollo/venv/tf/bin/pip install --no-cache-dir \
            -i https://pypi.tuna.tsinghua.edu.cn/simple \
            "tensorflow==2.16.*" \
      || /opt/apollo/venv/tf/bin/pip install --no-cache-dir \
            "tensorflow==2.16.*" \
    ) && \
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '# Source this file (or run "activate_tf") to get a python with TensorFlow.' \
        '# Do NOT activate it before running bazel — bazel needs the system python.' \
        'export TF_VENV=/opt/apollo/venv/tf' \
        'alias activate_tf="source ${TF_VENV}/bin/activate"' \
        > /etc/profile.d/apollo_tf_venv.sh && \
    chmod +x /etc/profile.d/apollo_tf_venv.sh

WORKDIR /apollo