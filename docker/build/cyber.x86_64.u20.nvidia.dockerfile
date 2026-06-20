# CyberRT image for Ubuntu 20.04 (focal) + Python 3.10 (deadsnakes) + CUDA 11.8.
#
# This combination is the *recommended* one when:
#   - you need glibc >= 2.28 (focal ships 2.31)
#   - you need python >= 3.10 (installed via deadsnakes PPA)
#   - you want to stay close to Apollo's existing third-party stack
#     (cuDNN 8.x / TensorRT 8.x / paddle / libtorch 1.13 all have official
#      CUDA 11 builds).
#
# Build context: docker/build/
ARG BASE_IMAGE=nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04
FROM ${BASE_IMAGE}

ARG APOLLO_DIST=stable
ARG GEOLOC=cn
ARG CLEAN_DEPS=yes
ARG INSTALL_MODE=build

LABEL maintainer="apollo-dev"
LABEL version="u20-1.0"
LABEL description="Apollo CyberRT dev image on Ubuntu 20.04 + Python 3.10 + CUDA 11.8"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TZ=Asia/Shanghai
ENV PATH=/opt/apollo/sysroot/bin:$PATH
ENV APOLLO_DIST=${APOLLO_DIST}

RUN mkdir -p /etc && echo "ubuntu_release=20.04" >  /etc/apollo.conf \
    && echo "stage=cyber" >> /etc/apollo.conf

COPY installers /opt/apollo/installers
COPY rcfiles  /opt/apollo/rcfiles

ENV http_proxy="http://127.0.0.1:7897"
ENV https_proxy="http://127.0.0.1:7897"

# 1) Minimal env: apt sources, python3.10 (deadsnakes), gcc-9 toolchain.
RUN bash /opt/apollo/installers/install_minimal_environment_u20.sh ${GEOLOC}

# 2) CMake.
RUN bash /opt/apollo/installers/install_cmake.sh

# 3) CyberRT deps (no glibc patch needed; focal already has 2.31).
RUN bash /opt/apollo/installers/install_cyber_deps_modern.sh ${INSTALL_MODE}

# 4) LLVM / clang, QA tooling, visualizer deps, bazel.
RUN bash /opt/apollo/installers/install_llvm_clang.sh || true
RUN bash /opt/apollo/installers/install_qa_tools.sh || true
RUN bash /opt/apollo/installers/install_visualizer_deps.sh || true
RUN bash /opt/apollo/installers/install_bazel.sh

RUN bash /opt/apollo/installers/post_install.sh cyber || true

ENV http_proxy=""
ENV https_proxy=""

WORKDIR /apollo