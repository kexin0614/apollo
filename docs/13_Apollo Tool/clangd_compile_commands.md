# 为 clangd 生成 compile_commands.json

本文档介绍如何在 Apollo 仓库中生成 `compile_commands.json`，从而让
[clangd](https://clangd.llvm.org/)（VSCode `clangd` 插件、Neovim、CLion 等）
获得准确的 C++ 代码补全、跳转、悬停与诊断能力。

Apollo 使用 **Bazel** 构建（`apollo.sh build` 最终调用 `bazel build`），
仓库本身原先没有内置生成 `compile_commands.json` 的工具。我们集成了社区事实
标准 [hedron_compile_commands](https://github.com/hedronvision/bazel-compile-commands-extractor)
来完成这一工作，并提供了一键脚本。

## 一、前置条件

- 已能正常使用 `apollo.sh build` 编译（即 Bazel 环境就绪）。
- 已安装 clangd（建议版本 >= 12）。VSCode 用户安装官方
  [`clangd` 插件](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.vscode-clangd)，
  并**禁用** VSCode 自带的 C/C++ IntelliSense（Microsoft `C/C++` 插件的
  IntelliSense 引擎），避免两者冲突。

## 二、生成 compile_commands.json

在仓库根目录执行（推荐方式）：

```bash
bash scripts/gen_compile_commands.sh
```

或者直接使用 Bazel：

```bash
bazel run //:refresh_compile_commands
```

执行成功后，会在仓库根目录生成 `compile_commands.json`。

> 说明：
> - 首次运行会下载 `hedron_compile_commands` 并分析全部 C++ 目标，
>   Apollo 代码量较大，可能耗时较久，请耐心等待。
> - 之后当新增源文件、修改 `BUILD` 或依赖变化导致补全不准时，重新运行
>   上述命令即可刷新。

### 针对 GPU 构建

如果你的代码依赖 GPU（CUDA / ROCm）相关宏与头文件，使用 GPU 模式生成，
其编译命令与 `apollo.sh build --config=gpu` 对齐：

```bash
bash scripts/gen_compile_commands.sh --config=gpu
# 等价于:
bazel run //:refresh_compile_commands_gpu
```

### 与 apollo.sh build 的 flag 一致性

`apollo.sh build` 最终执行的命令形如：

```bash
bazel build <CMDLINE_OPTIONS> <job_args> -- <targets>
```

其中：

- `.bazelrc` / `tools/bazel.rc` 中的全局 flag（如 `--cxxopt=-std=c++14`、
  各类 `--copt=-Werror=*`、`--define` 等）会被 `bazel run //:refresh_compile_commands`
  **自动继承**，无需重复设置；
- `apollo.sh build` 还在**命令行额外注入**了若干不在 `.bazelrc` 中的 flag，
  这些已在根 `BUILD` 的 `refresh_compile_commands` / `refresh_compile_commands_gpu`
  目标中逐一对齐：
  - `--config=cpu`（默认）或 `--config=gpu --config=nvidia`（GPU 模式）；
  - `--define ENABLE_PROFILER=true`（默认开启）；
  - `--copt=-mavx2 --host_copt=-mavx2`（x86_64 平台的 `job_args`）。

因此生成的 `compile_commands.json` 中的编译参数与 `apollo.sh build` 基本一致，
clangd 的诊断/补全结果与实际编译保持吻合。

> 注意：
> - 若你的实际构建使用了非默认参数（例如 `aarch64` 平台用的是
>   `--copt=-march=native` 而非 `-mavx2`，或自定义了 `CUSTOM_JOB_ARGS`），
>   可相应修改根 `BUILD` 中的 `APOLLO_CPU_BUILD_FLAGS` / `APOLLO_GPU_BUILD_FLAGS`
>   后重新生成。
> - clangd 使用 `clang` 解析，`.clangd` 已移除少数 GCC 专有、clang 不识别的
>   参数（如 `-fno-canonical-system-headers`），这不影响补全准确性。

## 三、clangd 配置

仓库根目录已提供 `.clangd` 配置文件，主要做了：

- 移除 GCC 专有、clangd 不识别的编译参数（如 `-fno-canonical-system-headers`），
  避免无意义的报错；
- 显式指定 `-std=c++14`，与 `apollo.sh build` 保持一致；
- 开启后台索引（全工程跳转/查找）与 inlay hints。

VSCode 用户可在 `settings.json` 中确认/添加：

```jsonc
{
  // 让 clangd 在仓库根目录寻找 compile_commands.json
  "clangd.arguments": [
    "--compile-commands-dir=${workspaceFolder}",
    "--background-index",
    "--clang-tidy",
    "--header-insertion=never"
  ]
}
```

## 四、常见问题

1. **打开文件后补全没反应 / 一直在 indexing**
   clangd 正在后台建立索引，首次需要一些时间，等待状态栏的 indexing 完成即可。

2. **找不到某些头文件 / 补全不全**
   通常是因为对应的 target 还没被纳入提取范围或源码有新增。重新执行
   `bash scripts/gen_compile_commands.sh` 刷新即可。

3. **与 Microsoft C/C++ 插件冲突**
   请关闭 Microsoft `C/C++` 插件的 IntelliSense（将 `C_Cpp.intelliSenseEngine`
   设为 `disabled`），统一使用 clangd。

4. **生成物是否需要提交到 Git？**
   不需要。`compile_commands.json` 与本机路径相关，已加入 `.gitignore`。

## 五、涉及的文件

| 文件 | 作用 |
| --- | --- |
| `WORKSPACE` / `WORKSPACE.source` | 引入 `hedron_compile_commands` 依赖 |
| `BUILD` | 定义 `//:refresh_compile_commands` 目标 |
| `scripts/gen_compile_commands.sh` | 一键生成脚本（封装 `bazel run`） |
| `.clangd` | clangd 行为配置 |
| `.gitignore` | 忽略生成物 `compile_commands.json` 等 |