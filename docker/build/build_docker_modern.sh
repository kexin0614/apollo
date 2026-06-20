#!/usr/bin/env bash
###############################################################################
# Build Apollo Cyber/Dev Docker images on a "modern" base OS.
#
# Two flavors are provided:
#   --os u20  ->  Ubuntu 20.04 + Python 3.10 (deadsnakes) + CUDA 11.8 (RECOMMENDED)
#   --os u22  ->  Ubuntu 22.04 + Python 3.10 (system)     + CUDA 12.x   (cutting edge)
#
# Default = u20 because it stays closest to Apollo's official third-party
# stack (cuDNN8 / TensorRT8 / paddle / libtorch 1.13 all have mature CUDA-11
# builds).
#
# All defaults assume mainland-China network access:
#   - aliyun apt mirror
#   - tsinghua pypi mirror
#   - daocloud / aliyun docker registry mirror (configure in daemon.json)
#
# Examples:
#   bash build_docker_modern.sh --os u20 -s cyber
#   bash build_docker_modern.sh --os u20 -s dev
#   bash build_docker_modern.sh --os u22 -s cyber
###############################################################################
set -e

APOLLO_REPO="apolloauto/apollo"
TARGET_ARCH="x86_64"
TARGET_GPU="nvidia"
TARGET_GEOLOC="cn"
INSTALL_MODE="build"
APOLLO_DIST="stable"

OS_VARIANT="u20"             # u20 | u22
BASE_IMAGE=""
STAGE=""
PREV_TIMESTAMP=""
USE_CACHE=1
DRY_RUN=0

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

function info()    { echo -e "[\033[34mINFO\033[0m] $*"; }
function warning() { echo -e "[\033[33mWARN\033[0m] $*"; }
function error()   { echo -e "[\033[31mERR \033[0m] $*"; }

function default_base_for_os() {
    case "$1" in
        u20) echo "nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04" ;;
        u22) echo "nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04"  ;;
        *)   echo ""; return 1 ;;
    esac
}

function ubuntu_lts_for_os() {
    case "$1" in
        u20) echo "20.04" ;;
        u22) echo "22.04" ;;
    esac
}

function print_usage() {
    cat <<EOF
Usage: $(basename "$0") -s <stage> [--os u20|u22] [other options]

Required:
  -s, --stage <cyber|dev>      Which stage to build.

Options:
  --os <u20|u22>               OS variant (default: u20).
                                 u20: Ubuntu 20.04 + Py3.10 + CUDA 11.8 (recommended)
                                 u22: Ubuntu 22.04 + Py3.10 + CUDA 12.x
  --base <image>               Override base image. Defaults:
                                 u20 cyber: nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04
                                 u22 cyber: nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
                                 dev      : auto-detect latest local cyber image of same OS.
  -t, --timestamp <ts>         For stage=dev, the timestamp suffix of the
                               cyber image to build upon (yyyymmdd_HHMM).
  -m, --mode <build|download>  INSTALL_MODE (default: build, recommended).
  -g, --geo  <cn|us>           GEOLOC (default: cn).
  -d, --dist <stable|testing>  Apollo distribution (default: stable).
  -c, --clean                  docker build --no-cache=true.
  --dry                        Print the docker command and exit.
  -h, --help                   Show this help.
EOF
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--stage)      STAGE="$2"; shift 2;;
            --os)            OS_VARIANT="$2"; shift 2;;
            --base)          BASE_IMAGE="$2"; shift 2;;
            -t|--timestamp)  PREV_TIMESTAMP="$2"; shift 2;;
            -m|--mode)       INSTALL_MODE="$2"; shift 2;;
            -g|--geo)        TARGET_GEOLOC="$2"; shift 2;;
            -d|--dist)       APOLLO_DIST="$2"; shift 2;;
            -c|--clean)      USE_CACHE=0; shift;;
            --dry)           DRY_RUN=1; shift;;
            -h|--help)       print_usage; exit 0;;
            *) error "Unknown option: $1"; print_usage; exit 1;;
        esac
    done

    [[ -z "${STAGE}" ]] && { error "Missing -s/--stage"; print_usage; exit 1; }
    case "${STAGE}" in cyber|dev) ;; *) error "stage must be cyber|dev"; exit 1;; esac
    case "${OS_VARIANT}" in u20|u22) ;; *) error "--os must be u20|u22"; exit 1;; esac
}

function pick_latest_cyber_image() {
    local lts; lts="$(ubuntu_lts_for_os "${OS_VARIANT}")"
    docker images --format '{{.Repository}}:{{.Tag}}' \
        | grep -E "^${APOLLO_REPO}:cyber-${TARGET_ARCH}-${TARGET_GPU}-${lts}-" \
        | sort | tail -n 1
}

function resolve_base_image() {
    if [[ -n "${BASE_IMAGE}" ]]; then return; fi

    if [[ "${STAGE}" == "cyber" ]]; then
        BASE_IMAGE="$(default_base_for_os "${OS_VARIANT}")"
        return
    fi

    # stage == dev: derive from cyber image of the same OS.
    local lts; lts="$(ubuntu_lts_for_os "${OS_VARIANT}")"
    if [[ -n "${PREV_TIMESTAMP}" ]]; then
        BASE_IMAGE="${APOLLO_REPO}:cyber-${TARGET_ARCH}-${TARGET_GPU}-${lts}-${PREV_TIMESTAMP}"
    else
        local found; found="$(pick_latest_cyber_image)"
        if [[ -z "${found}" ]]; then
            error "No local cyber image found for OS=${OS_VARIANT}. " \
                  "Build cyber first or pass --base."
            exit 1
        fi
        BASE_IMAGE="${found}"
        info "Auto-detected base cyber image: ${BASE_IMAGE}"
    fi
}

function compute_image_out() {
    local ts; ts="$(date +%Y%m%d_%H%M)"
    local lts; lts="$(ubuntu_lts_for_os "${OS_VARIANT}")"
    local arch_tag="${TARGET_ARCH}-${TARGET_GPU}"
    local dist_tag=""
    [[ "${APOLLO_DIST}" == "testing" ]] && dist_tag="-testing"

    if [[ "${STAGE}" == "cyber" ]]; then
        IMAGE_OUT="${APOLLO_REPO}:cyber-${arch_tag}-${lts}${dist_tag}-${ts}"
        DOCKERFILE="${CONTEXT_DIR}/cyber.x86_64.${OS_VARIANT}.nvidia.dockerfile"
    else
        IMAGE_OUT="${APOLLO_REPO}:dev-${arch_tag}-${lts}${dist_tag}-${ts}"
        DOCKERFILE="${CONTEXT_DIR}/dev.x86_64.${OS_VARIANT}.nvidia.dockerfile"
    fi
}

function preview() {
    cat <<EOF
=====.=====.===== Docker Build Preview (${STAGE} / ${OS_VARIANT}) =====
|  Dockerfile : ${DOCKERFILE}
|  FROM image : ${BASE_IMAGE}
|  OUT  image : ${IMAGE_OUT}
|  GEO  / DIST: ${TARGET_GEOLOC} / ${APOLLO_DIST}
|  INSTALL_MODE: ${INSTALL_MODE}
=====.=====.=====.=====.=====.=====.=====.=====.=====.=====.=====
EOF
}

function build() {
    local extra_args=""
    [[ "${USE_CACHE}" -eq 0 ]] && extra_args="--no-cache=true"

    local build_args=(
        --build-arg "BASE_IMAGE=${BASE_IMAGE}"
        --build-arg "GEOLOC=${TARGET_GEOLOC}"
        --build-arg "APOLLO_DIST=${APOLLO_DIST}"
        --build-arg "INSTALL_MODE=${INSTALL_MODE}"
        --build-arg "CLEAN_DEPS=yes"
    )

    # Disable BuildKit by default. BuildKit requires pulling
    # docker/dockerfile:1 frontend from docker.io which is often blocked in CN.
    # Users can opt in by exporting DOCKER_BUILDKIT=1 explicitly.
    : "${DOCKER_BUILDKIT:=0}"
    export DOCKER_BUILDKIT

    set -x
    docker build --network=host ${extra_args} \
        -t "${IMAGE_OUT}" \
        "${build_args[@]}" \
        -f "${DOCKERFILE}" \
        "${CONTEXT_DIR}"
    set +x
}

function main() {
    parse_args "$@"
    resolve_base_image
    compute_image_out
    preview
    if [[ "${DRY_RUN}" -gt 0 ]]; then
        info "Dry-run mode; not invoking docker."
        return 0
    fi
    build
    info "Done. Image: ${IMAGE_OUT}"
}

main "$@"