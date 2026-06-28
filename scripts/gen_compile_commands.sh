#! /usr/bin/env bash

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

# 为 clangd 生成 compile_commands.json。
#
# 该脚本基于 hedron_compile_commands (已在 WORKSPACE 中集成),
# 通过 `bazel run //:refresh_compile_commands` 提取与 `apollo.sh build`
# 一致的编译命令, 并在仓库根目录生成 compile_commands.json,
# 供 clangd / VSCode clangd 插件使用。
#
# 用法:
#   bash scripts/gen_compile_commands.sh              # CPU 模式 (默认)
#   bash scripts/gen_compile_commands.sh --config=gpu # GPU/NVIDIA 模式
#
# flag 一致性:
#   生成的编译命令与 `apollo.sh build` 对齐:
#     - 继承 .bazelrc / tools/bazel.rc 中的全局 flag (含 -std=c++14 等);
#     - 额外对齐 apollo.sh build 在命令行注入的 flag:
#       --config=cpu/gpu, --define ENABLE_PROFILER=true, --copt=-mavx2 等。
#   这些命令行注入 flag 定义在根 BUILD 的 refresh_compile_commands 目标中。
#
# 说明:
#   - 首次运行会拉取 hedron_compile_commands 并分析全部 C++ 目标,
#     Apollo 代码量大, 可能耗时较久, 请耐心等待。
#   - 生成的 compile_commands.json 位于仓库根目录, clangd 会自动识别。
#   - 如需重新生成 (例如新增了源文件或修改了 BUILD), 再次运行本脚本即可。

set -e

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${TOP_DIR}/scripts/apollo_base.sh"

function main() {
  # 解析是否使用 GPU 模式。GPU/CPU 对应的编译 flag 定义在根 BUILD 的不同
  # target 中 (refresh_compile_commands / refresh_compile_commands_gpu),
  # 因此这里根据参数选择对应 target, 而非把 flag 透传给被分析的目标。
  local target="//:refresh_compile_commands"
  local mode="CPU"
  for arg in "$@"; do
    case "${arg}" in
      --config=gpu | --config=nvidia | --config=amd | gpu | nvidia | amd)
        target="//:refresh_compile_commands_gpu"
        mode="GPU"
        ;;
    esac
  done

  info "开始为 clangd 生成 compile_commands.json (${mode} 模式) ..."
  info "(基于 hedron_compile_commands, 首次运行可能较慢)"

  pushd "${TOP_DIR}" > /dev/null
  bazel run "${target}"
  popd > /dev/null

  if [ -f "${TOP_DIR}/compile_commands.json" ]; then
    success "compile_commands.json 已生成于: ${TOP_DIR}/compile_commands.json"
    info "现在可以在 VSCode 中使用 clangd 插件获取 C++ 补全。"
  else
    error "未找到 compile_commands.json, 生成可能失败, 请检查上方日志。"
    exit 1
  fi
}

main "$@"
