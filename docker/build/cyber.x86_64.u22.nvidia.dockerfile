# CyberRT image for Ubuntu 22.04 (jammy) + Python 3.10 + CUDA 12 (NVIDIA GPU)
#
# Build context: docker/build/
# Default BASE_IMAGE: nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
#
# CN mirror tip: you can pre-pull the base image via DaoCloud / aliyun:
#     docker pull docker.m.daocloud.io/nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
#     docker tag  docker.m.daocloud.io/nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04 \
#                 nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
ARG BASE_IMAGE=nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
FROM ${BASE_IMAGE}

ARG APOLLO_DIST=stable
ARG GEOLOC=cn
ARG CLEAN_DEPS=yes
ARG INSTALL_MODE=build

LABEL maintainer="apollo-dev"
LABEL version="u22-1.0"
LABEL description="Apollo CyberRT dev image on Ubuntu 22.04 + Python 3.10"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TZ=Asia/Shanghai
ENV PATH=/opt/apollo/sysroot/bin:$PATH
ENV APOLLO_DIST=${APOLLO_DIST}

# Mark this image as ubuntu22 so installers can branch when needed.
RUN mkdir -p /etc && echo "ubuntu_release=22.04" >  /etc/apollo.conf \
    && echo "stage=cyber" >> /etc/apollo.conf

COPY installers /opt/apollo/installers
COPY rcfiles  /opt/apollo/rcfiles

# 1) Minimal env: apt sources, python3.10, basic toolchain.
RUN bash /opt/apollo/installers/install_minimal_environment_u22.sh ${GEOLOC}

# 2) CMake (installer downloads a recent prebuilt; works on 22.04).
RUN bash /opt/apollo/installers/install_cmake.sh

# 3) CyberRT deps (protobuf, fast-rtps, abseil, gflags/glog).
#    NOTE: the original install_cyber_deps.sh trailing block patches glibc to
#    2.31 for ubuntu18; that is unnecessary (and harmful) on 22.04 which ships
#    glibc 2.35. We invoke a wrapper that strips that step.
RUN bash /opt/apollo/installers/install_cyber_deps_modern.sh ${INSTALL_MODE}

# 4) LLVM / clang, QA tooling, visualizer deps, bazel.
RUN bash /opt/apollo/installers/install_llvm_clang.sh || true
RUN bash /opt/apollo/installers/install_qa_tools.sh || true
RUN bash /opt/apollo/installers/install_visualizer_deps.sh || true
RUN bash /opt/apollo/installers/install_bazel.sh

# 5) post install hook
RUN bash /opt/apollo/installers/post_install.sh cyber || true

WORKDIR /apollo