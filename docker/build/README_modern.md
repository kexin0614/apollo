# Apollo Docker 镜像 — 现代基础镜像（Python 3.10）

本目录新增一套自定义构建文件，用于在比官方 18.04 baseline 更新的系统上
构建 Apollo CyberRT / Dev 镜像，**满足 `glibc ≥ 2.28` 且 `python ≥ 3.10`**
的约束。提供两个变体（默认 cn 国内源）：

| 变体 | 系统 | Python | CUDA / cuDNN | 推荐度 | 说明 |
| ---- | ---- | ------ | ------------- | ------ | ---- |
| **u20** | Ubuntu 20.04 (focal, glibc 2.31) | 3.10（deadsnakes PPA） | 11.8 / 8.x | ⭐⭐⭐ 推荐 | 与 Apollo 现有第三方栈兼容性最好（cuDNN8 / TRT8 / paddle / libtorch 1.13 都有官方 cu118 包） |
| u22 | Ubuntu 22.04 (jammy, glibc 2.35) | 3.10（系统默认） | 12.4 / 9.x | ⭐ 实验 | 系统更新，但 CUDA 12 与 Apollo 旧依赖兼容性差，需要更多源码修改 |

> Apollo 官方仅预构建 18.04 镜像；u20 / u22 镜像需要在本地按下面步骤构建。

## 新增文件

```
docker/build/
├── cyber.x86_64.u20.nvidia.dockerfile          # u20 cyber
├── dev.x86_64.u20.nvidia.dockerfile            # u20 dev
├── cyber.x86_64.u22.nvidia.dockerfile          # u22 cyber
├── dev.x86_64.u22.nvidia.dockerfile            # u22 dev
├── build_docker_modern.sh                      # 一键构建脚本（支持 --os u20/u22）
├── README_modern.md                            # 本文档
├── installers/
│   ├── install_minimal_environment_u20.sh      # focal + py3.10(deadsnakes) + gcc-9
│   ├── install_minimal_environment_u22.sh      # jammy + py3.10(系统) + gcc-11
│   └── install_cyber_deps_modern.sh            # 跳过 18.04 libc 补丁的 cyber-deps wrapper
└── rcfiles/
    ├── sources.list.cn.x86_64.u20              # aliyun focal apt 源
    └── sources.list.cn.x86_64.u22              # aliyun jammy apt 源
```

## 国内源策略

- **APT**：aliyun（focal/jammy + nvidia-cuda 镜像）。
- **PyPI**：清华源 `pypi.tuna.tsinghua.edu.cn/simple`，构建期通过
  `pip config set global.index-url` 持久化。
- **Docker registry**：建议在 `/etc/docker/daemon.json` 配置：
  ```json
  {
    "registry-mirrors": [
      "https://docker.m.daocloud.io",
      "https://dockerproxy.com",
      "https://hub-mirror.c.163.com"
    ]
  }
  ```
  然后 `sudo systemctl restart docker`。这样拉取
  `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04` 等基础镜像也走国内。

## 一键构建

```bash
cd docker/build

# 推荐：u20 + CUDA11.8 + Python3.10
bash build_docker_modern.sh -s cyber              # 默认 --os u20
bash build_docker_modern.sh -s dev                # 自动找最新本地 cyber 镜像

# 或显式指定
bash build_docker_modern.sh --os u20 -s cyber
bash build_docker_modern.sh --os u20 -s dev -t 20240101_1200

# 想用 22.04 + CUDA12 实验镜像：
bash build_docker_modern.sh --os u22 -s cyber
bash build_docker_modern.sh --os u22 -s dev
```

常用参数：

| 参数 | 含义 | 默认 |
| --- | --- | --- |
| `-s, --stage cyber\|dev` | 阶段 | 必填 |
| `--os u20\|u22` | OS 变体 | `u20` |
| `--base <image>` | 覆盖基础镜像 | 见下表 |
| `-t, --timestamp` | dev 阶段指定 cyber tag 时间戳 | 自动找最新 |
| `-m, --mode build\|download` | INSTALL_MODE | `build`（建议） |
| `-g, --geo cn\|us` | 镜像源地域 | `cn` |
| `-d, --dist stable\|testing` | apollo 渠道 | `stable` |
| `-c, --clean` | `--no-cache` 重建 | 否 |
| `--dry` | 仅打印 docker 命令 | 否 |

默认基础镜像：

| `--os` | 默认 base image |
| --- | --- |
| u20 | `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04` |
| u22 | `nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04` |

## 验证 cyber 镜像

构建完 cyber 镜像后，建议先做一次健康检查，确认容器内的工具链、第三方依赖
和 cyber 框架本身都能正常工作：

```bash
# 自动选择本地最新的 cyber 镜像（cyber-x86_64-nvidia-20.04-XXXX 或 22.04-XXXX）
bash docker/build/verify_cyber_image.sh

# 或指定具体 tag
bash docker/build/verify_cyber_image.sh apolloauto/apollo:cyber-x86_64-nvidia-20.04-20260615_0026
```

脚本会以容器形式启动镜像（`/apollo` 自动 bind-mount 当前仓库），依次检查：

1. **OS / glibc / gcc 版本**：确认确实是 focal/jammy + glibc ≥ 2.31。
2. **Python**：确认 `python3 --version` 与预期一致；`Python.h` 存在
   （否则 pybind11 / cyber python 绑定会编译不过）。
3. **bazel**：确认 `bazel --version` 输出 5.2.0（或更高）。
4. **Cyber 第三方依赖**：检查 `/usr/local/fast-rtps`、protobuf / abseil /
   gflags / glog 的头文件和动态库已 ldconfig 注册。
5. **Cyber 框架编译**：`bazel build //cyber/...`（首次 20–60 分钟）。
6. **Talker / Listener 端到端**：跑 `cyber/examples/talker` 和 `listener`，
   确认 DDS（fast-rtps）层正确收发消息。

只想做 30 秒级的快速冒烟测试（跳过 5 / 6 的编译与运行）：
```bash
SKIP_BUILD=1 bash docker/build/verify_cyber_image.sh
```

任何一项 `[FAIL]` 都意味着镜像有问题；`[WARN]` 通常可以忽略（例如某个
header 不在常见路径下，但 `ldconfig` 能找到对应 .so）。

> **提示**：步骤 5 实际上等价于把 cyber 框架完整编译一次，比单纯"镜像是否
> 启动正常"严格得多。如果你只关心 dev 阶段后续构建会不会过，运行一次
> 完整验证就足够。

## 启动开发容器并验证（推荐用官方 `dev_start.sh`）

直接复用 Apollo 官方的容器启动脚本即可，无需为这套现代镜像单独写启动逻辑。
关键是用 `-t` 指定刚构建出来的本地 tag、用 `-l` 强制使用本地镜像（不去 pull）：

```bash
# 1) 找到刚构建好的 dev 镜像 tag
docker images | grep 'apolloauto/apollo:dev-x86_64-nvidia-20.04-'

# 2) 用官方脚本启动（-l 用本地镜像，-t 指定 tag，-y 跳过交互式协议确认）
bash docker/scripts/dev_start.sh -l -y \
     -t dev-x86_64-nvidia-20.04-<timestamp>

# 3) 进入容器
bash docker/scripts/dev_into.sh
```

> 说明：`dev_start.sh` 默认的 `VERSION_X86_64` 仍指向官方 18.04 镜像，
> 所以**必须**用 `-t` 覆盖成你本地的 u20/u22 tag。如果嫌每次都敲 `-t`，
> 也可以把脚本顶部的 `VERSION_X86_64="dev-x86_64-18.04-..."` 临时改成你的
> tag，但更推荐用 `-t` 参数，避免改动受版本管理的官方脚本。

### 在容器内验证（编译 + 单测 planning 模块）

进入容器后，用本目录提供的一键脚本（封装了官方 `./apollo.sh` 入口）：

```bash
# 容器内
bash docker/build/verify_dev_in_container.sh
```

它依次做三件事：

1. **dev 镜像专属健康检查**：
   - `/usr/local/libtorch_cpu` / `/usr/local/libtorch_gpu` 是否就位
     （CUDA 镜像缺 `libtorch_gpu` 直接判 FAIL，见 Q14）；
   - 系统 python 的 `google.protobuf` 必须是 **5.x**（确认 TF venv 没污染
     系统解释器，见 Q13）；
   - TF venv `/opt/apollo/venv/tf` 能否 `import tensorflow`；
   - `bazel --version`。
2. **编译 planning**：在 CUDA 镜像上用 `./apollo.sh build_nvidia planning`，
   CPU 镜像上用 `./apollo.sh build_cpu planning`。
3. **跑 planning 单测**：`./apollo.sh test planning`。

常用开关：

```bash
SKIP_BUILD=1 bash docker/build/verify_dev_in_container.sh   # 只做第 1 步健康检查（秒级）
SKIP_TEST=1  bash docker/build/verify_dev_in_container.sh   # 编译 planning 但不跑单测
BUILD_CMD=build_gpu bash docker/build/verify_dev_in_container.sh  # 手动指定 apollo.sh 的 build 动词
```

### 不想用脚本？直接敲官方命令

脚本本质上就是下面这几行，你完全可以在容器里手动执行：

```bash
# 容器内，/apollo 目录下
./apollo.sh config            # 首次需要，生成 bazel 配置（交互式按提示选 GPU/CPU 即可）

# 编译 planning（GPU 镜像）
./apollo.sh build_nvidia planning
#   CPU 镜像则用： ./apollo.sh build_cpu planning

# 跑 planning 单元测试
./apollo.sh test planning

# 也可以直接用 bazel（apollo.sh 底层就是调它）
bazel build //modules/planning/...
bazel test  //modules/planning/...
```

> 首次 `build` 会拉取大量 bazel 依赖并编译 cyber + planning 全链路，耗时较长
> （视机器 20 分钟到 1 小时不等）；后续增量编译很快。

## 与官方 18.04 镜像的差异

| 维度 | 官方 18.04 | u20（推荐） | u22 |
| --- | --- | --- | --- |
| glibc | 2.27（镜像内补丁到 2.31） | 2.31 | 2.35 |
| Python | 3.6 | 3.10（deadsnakes） | 3.10（系统默认） |
| GCC | 7 | 9 | 11 |
| CUDA / cuDNN / TensorRT | 11.1 / 8.0 / 7.2 | 11.8 / 8.x / 8.x | 12.4 / 9.x / 10.x |
| TensorFlow | 2.3 | 2.13 | 2.13 |
| APT 源（CN） | tsinghua bionic | aliyun focal | aliyun jammy |
| Docker registry | docker.io | daocloud / 阿里云 | daocloud / 阿里云 |

## 已知风险与建议

1. **优先用 u20**：Apollo perception 等模块大量依赖 cuDNN8、TensorRT8、
   paddle-inference / libtorch 的 cu118 二进制，u20 镜像几乎可以"开箱即用"
   完成 cyber 框架与大部分模块的编译。u22 + CUDA12 仍然推荐用于纯 cyber
   框架试水或上层 Python 工具，不建议直接用于完整 perception 编译。
2. **不要使用 `INSTALL_MODE=download`**：apolloauto deb 仓库基于 bionic，
   在 focal/jammy 上会出现 `libstdc++` / `libtinfo` 等依赖冲突。
3. **deadsnakes PPA 是 u20 的关键**：`install_minimal_environment_u20.sh`
   使用它将 python3.10 设为默认 `python` / `python3`，并通过
   `bootstrap.pypa.io/get-pip.py` 重新拉起一份 py3.10 的 pip。如果你的网络
   无法访问 `launchpad.net`，可以预先在脚本头部添加镜像，例如：
   ```bash
   add-apt-repository -y "deb https://launchpad.proxy.ustclug.org/deadsnakes/ppa/ubuntu focal main"
   ```
4. **dev dockerfile 中部分 installer 使用 `|| true` 容错**（如
   `install_rsdriver.sh`、`install_livox_driver.sh`），用于规避国内访问
   GitHub Release 不稳。构建结束后请检查日志，若你需要这些传感器驱动，
   请进入容器后手动重跑对应脚本。
5. **glibc 兼容性**：focal 的 2.31 / jammy 的 2.35 都满足 ≥ 2.28；
   `install_cyber_deps_modern.sh` 显式跳过了原 18.04 流水线尾部的
   `libc6-2.31-ubuntu18` 补丁步骤，避免在新系统上引入冲突。

## 故障排查（FAQ）

### Q1: `failed to fetch oauth token ... auth.docker.io ... connection reset by peer` / `resolve image config for docker-image://docker.io/docker/dockerfile:1`

这是 BuildKit 在拉它自己的 frontend 镜像 `docker/dockerfile:1` 时国内网络
被重置导致。本仓库的 Dockerfile 已经移除了 `# syntax=docker/dockerfile:1`
头，**不需要 BuildKit**。`build_docker_modern.sh` 也已经默认设置了
`DOCKER_BUILDKIT=0`。请重新拉取本目录脚本/Dockerfile 的最新版本后再次构建。

如果你之前手动启用过 BuildKit（例如 shell 里 `export DOCKER_BUILDKIT=1`、
或在 daemon.json 中开启了 `"features": {"buildkit": true}`），可以：
- 临时禁用：`DOCKER_BUILDKIT=0 bash build_docker_modern.sh -s cyber`；
- 永久禁用：在 `/etc/docker/daemon.json` 中把 `"features.buildkit"` 设为 false 并重启 docker；
- 或者保留 BuildKit 但提前把 frontend 拉下来：
  ```bash
  docker pull docker.m.daocloud.io/docker/dockerfile:1
  docker tag  docker.m.daocloud.io/docker/dockerfile:1 docker/dockerfile:1
  ```

### Q2: 拉取 `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04` 极慢或超时

国内访问 docker.io 不稳。两种解法二选一：

**方案 A（推荐，一次配置永久生效）**：在 `/etc/docker/daemon.json` 中加入：
```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://hub-mirror.c.163.com"
  ]
}
```
保存后 `sudo systemctl restart docker`，再次执行 `bash build_docker_modern.sh ...` 即可。

**方案 B（一次性）**：手动从镜像源拉取并打 tag：
```bash
docker pull docker.m.daocloud.io/nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04
docker tag  docker.m.daocloud.io/nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04 \
            nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04
```
之后 docker build 会发现本地已经有该 tag，跳过远程拉取。

### Q3: 构建到安装 `python3.10` 时报 `Unable to locate package python3.10-dev`

deadsnakes PPA 的 GPG key 没拉下来导致整个 PPA 在 `apt-get update` 时被静默丢弃。
最新的 `install_minimal_environment_u20.sh` 已经改写为：

1. **先装好系统的 python3.8 工具链**（保证脚本无论如何都有可用的 python3）。
2. 通过 HTTPS（443 端口）从多个 keyserver mirror 获取 deadsnakes 的签名 key：
   - `https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x...`
   - `https://keys.openpgp.org/vks/v1/by-fingerprint/...`
3. 注册 PPA 时优先使用 `https://launchpad.proxy.ustclug.org/deadsnakes/ppa/ubuntu focal main`，
   失败则切到 `ppa.launchpadcontent.net`。
4. 最后 `apt install python3.10 python3.10-dev python3.10-venv python3.10-distutils`。
   只要 `python3.10-dev` 装失败，就**自动回退到 python3.8**（继续构建，不报错）。

> Apollo 的 Bazel 构建在编译 pybind11 等模块时**必须**有 `Python.h`，所以
> 单独的 python3.10 可执行文件不够用。脚本因此把 `python3.10-dev` 视为
> "必须成功"——它失败时会整体丢弃 3.10 的安装结果，回到 3.8。

#### 想要严格要求 python3.10（构建失败时立即 abort）

```bash
docker build \
    --build-arg INSTALL_MODE=build \
    --build-arg GEOLOC=cn \
    --build-arg DIST=stable \
    -e FORCE_PY310=1 \
    ...
```
（或在 Dockerfile 里 `ENV FORCE_PY310=1`。）

#### 想给 deadsnakes 的 key 一个完全离线的来源

在能联外网的机器上执行：
```bash
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF23C5A6CF475977595C89F51BA6932366A755776" \
     -o docker/build/rcfiles/deadsnakes.asc
```
然后在 `cyber.x86_64.u20.nvidia.dockerfile` 中追加一行：
```dockerfile
COPY rcfiles/deadsnakes.asc /etc/apt/keyrings/deadsnakes.asc
RUN gpg --no-default-keyring --keyring /etc/apt/keyrings/deadsnakes.gpg \
        --import /etc/apt/keyrings/deadsnakes.asc
```
再放在 `install_minimal_environment_u20.sh` 之前；脚本检测到 `${KEYRING}`
已存在会跳过下载。

#### 直接用代理

```bash
docker build --build-arg http_proxy=http://host:port \
             --build-arg https_proxy=http://host:port \
             ...
```

### Q4: 构建到 `install_fast-rtps.sh` 时报 `Remote branch release/1.5.0 not found in upstream origin`

eProsima 已经把 `Fast-RTPS` 重命名为 `Fast-DDS`，旧仓库的 `release/1.5.0` 分支
不复存在，所以 `INSTALL_MODE=build` 会卡死在 `git clone --branch release/1.5.0`。

修复：`install_cyber_deps_modern.sh` 已改为**强制对 fast-rtps 使用 download 模式**
（拉 Apollo 官方 CDN 上的 1.5.0 prebuilt tarball），其它依赖（protobuf / abseil /
gflags+glog）仍按你选的 `INSTALL_MODE` 走。这个 prebuilt 是静态布局、安装到
`/usr/local/fast-rtps`，对 focal 的 glibc 2.31 / jammy 的 2.35 都兼容。

如果你坚持要从源码编译 1.5.0，可以手动指向一个 tag 或 fork：
```bash
git clone --depth 1 --branch v1.5.0 https://github.com/eProsima/Fast-RTPS.git
# 然后 git submodule update --init && patch ... && cmake ... && make install
```
但这条路并不被这套现代镜像默认支持，需要你自行维护脚本。

### Q5: 构建到 `install_bazel.sh` 时长时间卡在 `Get:1 https://storage.googleapis.com/bazel-apt ...`

`storage.googleapis.com` 在国内大陆基本不可达，`apt install --only-upgrade bazel=5.2.0`
会一直卡在 48.6 MB 的下载上，直到超时。原脚本的逻辑是**先从 GitHub 下 3.7.1，
再用 apt 升级到 5.2.0**，第二步纯属冗余。

修复（已应用）：`install_bazel.sh` 直接把 `BAZEL_VERSION` 设为 `5.2.0`，
一次性从 GitHub Releases 下 `bazel_5.2.0-linux-x86_64.deb`（sha256 校验），
并删除尾部的 bazel-apt 源 + apt upgrade 步骤。这样整个 bazel 安装只走
GitHub 一个域名。

如果连 GitHub Releases 也很慢，可在构建时设代理：
```bash
docker build --build-arg http_proxy=http://host:port \
             --build-arg https_proxy=http://host:port \
             ...
```
或者把 `DOWNLOAD_LINK` 替换为 ghproxy 镜像：
```bash
DOWNLOAD_LINK="https://ghproxy.com/https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/${PKG_NAME}"
```

### Q6: 编译 cyber 时报 `fatal error: third_party/var/bvar/bvar.h: No such file or directory`

`third_party/var/...` 不是 Apollo 仓库里的源码，也不是 bazel external 依赖，
而是来自 Apollo 自己的 apt 包 **`bvar`**（brpc 的 bvar 子库），
通过 `apt install bvar` 装到 `/usr/local/include/third_party/var/...`。

问题在于该 apt 仓库（`apollo-pkg-beta.cdn.bcebos.com/apollo/core`）
**只在 `bionic` codename 下发布了 `bvar`**，在 `focal`/`jammy` 下都没有。
原 dockerfile 中 `bash install_pkg_repo.sh || true` 把这个失败吞掉了，
于是 cyber 一编译到 `cyber/statistics`、`cyber/transport/transmitter` 这些
依赖 `bvar` 的 TU 时就缺头文件。

修复（已应用）：新增 `installers/install_bvar.sh`，**直接从 Apollo 的 bionic
deb 仓库下载 `bvar_9.0.0-rc1-r1_amd64.deb`，用 `dpkg-deb -x` 解到 `/`**：
- 头文件落到 `/usr/local/include/third_party/var/...`，bazel 走 `-iquote /usr/local/include` 即可命中；
- 共享库 `libbvar.so` 落到 `/usr/local/lib/`，`ldconfig` 注册后 `-lbvar` 链接通过；
- 不走 `dpkg -i`，避开 dpkg 的 codename / Depends 检查。

只依赖 `libc6`，对 focal 的 glibc 2.31 / jammy 的 2.35 都兼容。
`install_cyber_deps_modern.sh` 已自动调用此脚本，重建 cyber 镜像即可。

如果你只想给**已经构建好的旧镜像**打补丁、不想重新跑整个构建，可以：
```bash
docker run --rm -v $(pwd):/apollo apolloauto/apollo:cyber-x86_64-nvidia-20.04-XXXX bash -lc '
  curl -fsSL https://apollo-pkg-beta.cdn.bcebos.com/apollo/core/pool/main/b/bvar/bvar_9.0.0-rc1-r1_amd64.deb \
       -o /tmp/bvar.deb && \
  dpkg-deb -x /tmp/bvar.deb / && ldconfig
'
# 然后用 docker commit 将这层提交到一个新 tag
```
但更推荐重新构建，避免镜像层级失控。

### Q7: 编译 cyber 时报 `fatal error: tinyxml2.h: No such file or directory`

`cyber/plugin_manager/plugin_description.cc` 直接 `#include <tinyxml2.h>`，
所以 cyber 镜像里必须有 `libtinyxml2-dev`。原 `install_fast-rtps.sh` 在末尾
有一段 `if [[ -n "${CLEAN_DEPS}" ]]; then apt_get_remove libtinyxml2-dev; fi`，
某些 INSTALL_MODE 下会把它清理掉，导致 cyber 编译时找不到头文件。

修复（已应用）：`install_cyber_deps_modern.sh` 在所有依赖安装完之后**无条件
重新装一次** `libasio-dev libtinyxml2-dev`，让 cyber 镜像层自包含。

### Q8: 启动 cyber 节点时 stderr 出现 `E ... third_party/var/bvar/variable.cpp:174] Already exposed '...'`

**这是上游已知行为，不是错误，可以忽略。** 只是日志噪音。

`cyber/transport/transmitter/transmitter.h:67~72` 在每个 `Transmitter`
构造时调一次 `statistics::Statistics::CreateAdder`，原实现**不带缓存**：
```cpp
return std::make_shared<::bvar::Adder<SampleT>>(expose_name);
```
而一个 `Writer` 内部会创建 4 个 transmitter（intra / shm / rtps + hybrid 包装），
共享同一个 `(node, channel)`，于是 bvar 的 expose 表里同名注册 4 次，
打 3 行 `Already exposed` 的 `[E]` 日志。bvar 容忍重复 expose，进程不会崩，
计数器也仍然正确，只是观感很难看。

修复（已应用，可选）：在 `cyber/statistics/statistics.h` 的 `CreateAdder<>`
里加了 `expose_name → shared_ptr<void>` 缓存（带互斥锁），同名 transmitter
共享一份 Adder，bvar 只 expose 一次。代价是 `send_adder_cache_` 多占一点
内存（每条 channel 1 个 entry，可忽略）。

如果想还原成上游行为（重新让那 3 行 ERROR 出现），在 `statistics.h` 把
`CreateAdder` 改回 `make_shared<Adder<>>(expose_name)` 直接 return 即可。

### Q9: dev 镜像构建到 `install_boost.sh` 时报 `bzip2: (stdin) is not a bzip2 file. tar: Child returned status 2`

JFrog 在 2024 年初撤掉了 `boostorg.jfrog.io` 这个免费 artifactory；旧的下载
URL（`https://boostorg.jfrog.io/artifactory/main/release/1.74.0/source/boost_1_74_0.tar.bz2`）
现在会 302 跳到 JFrog 的 landing 页（一份约 11KB 的 HTML），但
`download_if_not_cached` 在远程下载分支**没有做 SHA256 校验**，于是 wget
"成功下载" 11KB 的 HTML，紧接着 tar 一定会失败。

修复（已应用）：`install_boost.sh` 改为按顺序尝试一组**仍然在线**的镜像，
并在每个镜像下载完成后**显式校验 SHA256**，校验通过才进入解包。镜像列表：

1. `https://apollo-system.cdn.bcebos.com/archive/6.0/boost_1_74_0.tar.bz2`
   ——Apollo 自己的 bcebos CDN，国内最快，老的 6.0 镜像构建链路就在用，仍然在线。
2. `https://archives.boost.io/release/1.74.0/source/boost_1_74_0.tar.bz2`
   ——Boost 官方在迁出 jfrog 之后的新主站，全球 CDN。
3. `https://mirrors.aliyun.com/blfs/conglomeration/boost/boost_1_74_0.tar.bz2`
   ——aliyun BLFS 镜像，国内备选。
4. `https://sourceforge.net/projects/boost/files/boost/1.74.0/boost_1_74_0.tar.bz2/download`
   ——SourceForge 兜底，慢但极稳定。

任何一个镜像通过 SHA256 校验就立即停止重试。所有镜像都失败时，脚本会显式
`exit 1`（而不是再让 tar 去崩）。

如果你已经把 boost_1_74_0.tar.bz2 提前缓存在 `${LOCAL_HTTP_ADDR}` 上，那条
快速路径不受影响；脚本只是把"远程 fallback"那一段重写得更稳。

### Q10: dev 镜像构建到 `install_ffmpeg.sh` 末尾报 `E: Unable to locate package libvpx5 / libx264-152 / libx265-146`

ffmpeg 源码编译完成后，原脚本在 `CLEAN_DEPS` 分支里把 `libx264-dev / libx265-dev / libvpx-dev` 这些 -dev 包卸掉，然后再 `apt install` 一组**只含 .so 的运行时包**——目的是让 ffmpeg 二进制运行时仍能 dlopen 到对应的库，同时镜像可以瘦身。

问题在于这组运行时包名**带 SONAME 数字**，是 18.04 (bionic) 专属：

| 包名 | bionic 18.04 | focal 20.04 | jammy 22.04 |
| --- | --- | --- | --- |
| `libvpx5` | ✅ | ❌ 已是 `libvpx6` | ❌ `libvpx7` |
| `libx264-152` | ✅ | ❌ `libx264-155` | ❌ `libx264-163` |
| `libx265-146` | ✅ | ❌ `libx265-179` | ❌ `libx265-199` |
| `libopus0/libmp3lame0/libvorbis0a/libfdk-aac1/libass9/libtheora0` | ✅ | ✅ | ✅ |

每升一次 Ubuntu，前 3 个包名都会变一次。

修复（已应用，方案 B）：在 focal/jammy 上**保留 `-dev` 包，不再做 dev→runtime 替换**。`-dev` 包本来就是运行时包的严格超集（包含同一份 .so 加上头文件、符号链接），ffmpeg 二进制照样能 dlopen 到 `libx264.so.155 / libx265.so.179 / libvpx.so.6`，功能完全不受影响。代价是 dev 镜像约多 30 MB——dev 镜像本来就以"啥都有、方便容器内二次编译 OpenCV/ffmpeg"为目标，瘦身在 dev 阶段意义不大。

实现方式：在 `CLEAN_DEPS` 分支顶端 `. /etc/os-release` 取 `VERSION_CODENAME`：
- `bionic`：完全保留原 18.04 行为；
- 其它（focal/jammy/...）：**只**卸掉构建用的 `nasm yasm`，跳过 dev→runtime 替换并打 `info` 日志说明原因。

> 注：之前一版的 patch 在顶层脚本（非函数）里用了 `local _codename=`，
> 在 `set -e` 下 `local` 在函数外会立即报 `not in a function` 并退出，
> 已改为普通赋值。

如果未来想跨 Ubuntu 都做"瘦身 runtime 替换"，对应包名是：
- focal: `libvpx6 libx264-155 libx265-179`
- jammy: `libvpx7 libx264-163 libx265-199`

可在 `install_ffmpeg.sh` 的 `else` 分支里按 codename 加 `case` 处理；目前没有这么做，因为 dev 镜像不是瘦身目标。

### Q11: docker build 时报 `permission denied while trying to connect to docker daemon socket`

把当前用户加进 docker 组：
```bash
sudo usermod -aG docker "$USER" && newgrp docker
```

### Q12: dev 镜像构建到 `install_pkg_repo.sh` 时报 `Package 'bvar' has no installation candidate`

报错形如：
```
Package bvar is not available, but is referred to by another package.
This may mean that the package is missing, has been obsoleted, or
is only available from another source

E: Package 'bvar' has no installation candidate
```

根因和 Q6 是同一个：Apollo 的私有 apt 仓库
（`https://apollo-pkg-beta.cdn.bcebos.com/apollo/core`）**只在 `bionic` codename
下发布了 `bvar`**，在 `focal`/`jammy` 下没有。原 `install_pkg_repo.sh` 在
注册 apolloauto 源时直接用 `$VERSION_CODENAME`（也就是 focal/jammy），
然后 `apt install bvar`，于是必然失败：
- 要么 `apt-get update` 时 Release 文件 404，整个源被静默丢弃；
- 要么 update 成功但里面没有 focal/jammy 的 bvar，apt resolve 不出候选版本。

cyber 阶段我们已经通过 `install_bvar.sh`（直接抽取 bionic .deb）把 bvar
装到了 `/usr/local/include/third_party/var/...` + `/usr/local/lib/libbvar.so`，
完全够用——dev 阶段不应该再去碰 apt 这条死路。

修复（已应用）：`install_pkg_repo.sh` 现在会读取 `/etc/os-release` 的
`VERSION_CODENAME`：
1. **bionic**：行为与上游完全一致（注册 bionic 源 + `apt install bvar`）。
2. **focal / jammy**：
   - apt 源仍然注册，但 codename 强制改成 `bionic`，让 `apt-get update`
     可以正常解析 Release 文件（apolloauto 仓库里那些 deb 只依赖 `libc6`，
     在 focal/jammy 上 ABI 兼容）；
   - **跳过 `apt install bvar`**，改为调用 `install_bvar.sh`。该脚本是
     幂等的：cyber 阶段已经装好的话直接 `info "bvar already installed"`
     退出，dev 阶段的 layer 增量为 0。

同时把脚本里 `info` / `warning`（注意是 `warning`，不是 `warn`，与
`installer_base.sh` 保持一致）的日志函数名修正了一遍；并且把末尾
`sed -i ... /usr/include/flann/util/params.h` 改成存在性检查保护——
focal/jammy 的 PCL 切到了不再依赖该 flann 头的版本时，原命令会硬报
`No such file or directory` 直接 abort 掉整个 layer。

如果你只想给一个**已经构建到 `install_pkg_repo.sh` 失败的 dev 镜像**
打补丁、不重新跑整套构建，可以：
```bash
docker run --rm -v $(pwd):/apollo apolloauto/apollo:dev-x86_64-nvidia-20.04-XXXX bash -lc '
  bash /opt/apollo/installers/install_bvar.sh && \
  mkdir -p /opt/apollo/neo/data/log && chmod -R 777 /opt/apollo/neo
'
# 然后 docker commit 到一个新 tag
```
但更推荐重新构建，避免镜像层级失控。

### Q13: dev 镜像构建到末尾安装 `tensorflow==2.13.*` 时报 protobuf / numpy 等依赖冲突

报错形如：
```
ERROR: pip's dependency resolver does not currently take into account all the
packages that are installed. This behaviour is the source of the following
dependency conflicts.
grpcio-tools 1.70.0 requires protobuf<6.0dev,>=5.26.1, but you have
protobuf 4.25.9 which is incompatible.
```
（同一 RUN 里还能看到 typing_extensions / numpy / cryptography 也被降级。）

#### 根因

cyber 阶段已经把系统 python 的依赖锁定在 protobuf 5.x：

- `grpcio-tools 1.70` 依赖 `protobuf>=5.26,<6`；
- Apollo 自己的 C++ protobuf runtime 和 python 绑定（`cyber/python/...`）
  也是按 protobuf 5.x 的 API 生成的。

而 TensorFlow 的版本/protobuf 兼容矩阵是：

| TF 版本 | protobuf 要求 | Python | CUDA | 备注 |
| ------- | ------------- | ------ | ---- | ---- |
| 2.13.x  | `>=3.20.3,<4.24` | 3.8–3.11 | 11.8 | 强制 protobuf 4.x |
| 2.14.x  | `>=3.20.3,<5`    | 3.9–3.11 | 11.8 | 仍然 protobuf 4.x |
| 2.15.x  | `>=3.20.3,<5`    | 3.9–3.11 | 12.2 | 仍然 protobuf 4.x |
| 2.16.x  | `>=3.20.3,<5`    | 3.9–3.11 | 12.3 | 仍然 protobuf 4.x |
| 2.17.x  | `>=3.20.3,<5`    | 3.9–3.12 | 12.3 | 仍然 protobuf 4.x |
| 2.18+   | `>=3.20.3,<6`    | 3.9–3.12 | 12.3 | 第一个支持 protobuf 5 的版本，CUDA 已是 12.3 |

也就是说在 CUDA 11.8（u20 镜像）上：**TF 全系列都强制 protobuf<5**——
直接 `pip install` 一定会把 cyber 阶段装好的 protobuf 5.29 降级到 4.25，
不仅触发 grpcio-tools 的依赖冲突，还会让 cyber 自身的 python 绑定运行时
报 `protobuf C++ runtime mismatch`。

#### 修复（已应用）：把 TF 装进独立 venv

新版 `dev.x86_64.u20.nvidia.dockerfile` / `dev.x86_64.u22.nvidia.dockerfile`
不再向系统 python 安装 TF，而是创建一个隔离 venv：

- u20：`/opt/apollo/venv/tf` → `tensorflow==2.15.*`（CUDA 11.8 上最新可用）
- u22：`/opt/apollo/venv/tf` → `tensorflow==2.16.*`（CUDA 12 上更现代）

venv 内的 protobuf / numpy / cryptography 想怎么换都行，**完全不影响**
系统 python 的 protobuf 5.x，bazel 构建链路稳定。同时镜像里写了一个
`/etc/profile.d/apollo_tf_venv.sh`：

```bash
export TF_VENV=/opt/apollo/venv/tf
alias activate_tf="source ${TF_VENV}/bin/activate"
```

容器内使用方式：

```bash
# 默认 shell 仍是系统 python，可以直接跑 bazel
python3 -c "import google.protobuf; print(google.protobuf.__version__)"  # 5.29.x

# 需要 TF 时进入 venv
source /etc/profile.d/apollo_tf_venv.sh
activate_tf
python -c "import tensorflow as tf; print(tf.__version__)"               # 2.15.x / 2.16.x

# 用完退出
deactivate
```

> **重要**：**不要**在 `bazel build //...` 之前 `activate_tf`。bazel 用的是
> `python3` 这个解释器解析 BUILD/.bzl，里面只能见到系统 python 的依赖；
> 如果当前 shell 还在 venv 里，`python3` 会被指向 venv 的解释器，
> Apollo 的 protobuf 5.x 模块会立刻找不到。

#### 想严格冻结 TF 版本而不是接受补丁版本

把 dockerfile 里的 `"tensorflow==2.15.*"` 改成具体的 `"tensorflow==2.15.1"`
（u20）或 `"tensorflow==2.16.2"`（u22）即可。pinning 越严越能保证两次
构建拿到完全一致的二进制。

#### 完全不需要 TensorFlow

如果你只用 cyber + planning + dreamview，不跑任何依赖 TF 的 perception
模型，可以**整段删掉**这条 `RUN`。镜像会瘦下去 ~1.5 GB，构建时间也省一截。

### Q14: dev 镜像构建到 `install_libtorch.sh` 时打 `[WARNING] No nvidia-smi found.`

#### 现象

```
[WARNING] No nvidia-smi found.
[WARNING] No rocm-smi found.
```
之后 `libtorch_gpu` 这一段被静默跳过，最终镜像里只有 `/usr/local/libtorch_cpu`，
没有 `/usr/local/libtorch_gpu`。等到容器内 `bazel build //modules/perception/...`
时会报找不到 `libtorch_gpu`。

奇怪的是：进入**构建好的 cyber 镜像**里 `nvidia-smi` 是能跑的；为什么
**构建过程中**就找不到？

#### 根因：`docker build` 阶段没有 `nvidia-smi`

`install_libtorch.sh` 调用 `installer_base.sh` 里的 `determine_gpu_use_host`，
该函数用 `command -v nvidia-smi` 判断"是否要装 GPU 版 libtorch"。但是：

| 阶段 | nvidia-smi 是否可用 | 原因 |
| --- | --- | --- |
| `docker build` 时（构建沙箱内） | ❌ 不可用 | build 容器**不会**被 nvidia-container-runtime 注入；CUDA base image 里只有 CUDA toolkit 和库（`libcuda.so` / `libcudart.so` 等），**没有 `nvidia-smi` 二进制**——它由 `nvidia-container-toolkit` 在 `docker run --gpus all` 时从宿主机 bind-mount 进容器 |
| `docker run --gpus all ...` 时 | ✅ 可用 | nvidia-container-runtime 把 `/usr/bin/nvidia-smi`、`libnvidia-ml.so.1`、`libcuda.so.1` 等动态挂载进来 |

所以在 `docker build` 这一层探测一定失败，`USE_NVIDIA_GPU` 被置为 0，GPU
libtorch 被跳过。这不是镜像基础环境的问题，而是探测策略不适用于
build-time。

#### 修复（已应用）：build-time 显式开关 `APOLLO_GPU`

`install_libtorch.sh` 现在的判定顺序是：

1. 优先看环境变量 `APOLLO_GPU`：
   - `nvidia` → 强制装 CUDA libtorch_gpu；
   - `amd` → 强制装 ROCm libtorch_gpu；
   - `cpu` → 跳过 GPU libtorch（只装 CPU 版）；
   - `auto`（默认）→ 走步骤 2。
2. 在 `auto` 模式下：
   - 先跑原来的 `determine_gpu_use_host`（仅在你**真的把 GPU 暴露给了 build
     容器**——例如用了 `--gpus all` + nvidia-container-toolkit 1.7+ 的
     `csv` 模式——才会成功）；
   - 探测失败但检测到 `CUDA_VERSION` 环境变量或 `/usr/local/cuda` 存在时，
     **认为这是一个 CUDA base image，强制 USE_NVIDIA_GPU=1**。`u20` 镜像基
     于 `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04`，`CUDA_VERSION=11.8.0`
     是该 base image 的 ENV，命中此路径。

也就是说：**默认情况下你什么都不用改，重新构建 dev 镜像就会拿到带
libtorch_gpu 的版本**。`[WARNING] No nvidia-smi found.` 仍可能出现一行
（来自 `determine_gpu_use_host`），但紧接着会有一行 `info`：

```
[INFO] Detected CUDA toolkit (CUDA_VERSION=11.8.0, /usr/local/cuda exists)
       but no nvidia-smi (expected inside docker build). Assuming NVIDIA
       GPU target; set APOLLO_GPU=cpu to override.
```

随后 `libtorch_gpu` 正常下载安装。

#### 想强制 CPU-only 镜像

```bash
docker build --build-arg APOLLO_GPU=cpu ...
```
或直接 `ENV APOLLO_GPU=cpu`。

#### 想强制 ROCm（AMD）镜像

```bash
docker build --build-arg APOLLO_GPU=amd ...
```
> 注意：u20/u22 默认 base image 是 NVIDIA CUDA，要装 ROCm libtorch
> 你还需要把 base image 换成 ROCm 的 devel 镜像，并自行处理 `install_gpu_support.sh`
> 等其它 NVIDIA 专属步骤。

#### 还想保留旧的"严格按宿主机探测"行为？

```bash
docker build --build-arg APOLLO_GPU=auto ...
# 同时把 /usr/local/cuda 隐藏起来，或自己改写 install_libtorch.sh 把
# "CUDA_VERSION 兜底"那段删掉。
```
不推荐——这等于回到原来"默默装成 CPU 版"的坑里。

### Q15: dev 镜像构建到 venv 装 TF 时报 `Could not find a version that satisfies the requirement tensorflow==2.15.*`

完整报错：
```
Looking in indexes: https://pypi.tuna.tsinghua.edu.cn/simple
ERROR: Could not find a version that satisfies the requirement tensorflow==2.15.*
(from versions: 2.2.0, ..., 2.13.0, 2.13.1)
ERROR: No matching distribution found for tensorflow==2.15.*
```

#### 根因：清华 PyPI 镜像不全量同步 tensorflow

清华 `pypi.tuna.tsinghua.edu.cn` 出于带宽考虑，**只同步到 tensorflow 2.13.1**，
2.14 及以上的 wheel 不会出现在它的 simple index 里。这与 cuda、Python 版本
都无关——纯粹是镜像方的策略选择。

之前的 dockerfile 把"先清华后默认源"作为 fallback，但默认源也是清华
（cyber 阶段 `install_geo_adjustment.sh` 用 `pip config set global.index-url`
把它写进了 `/etc/pip.conf`），所以 fallback 实际上等于试了同一个源两次，
都失败。

#### 修复（已应用）：依次尝试三个有完整 tensorflow 索引的源

新版 `dev.x86_64.u20.nvidia.dockerfile` 在装 TF 时**绕开**清华源，依次尝试：

| 顺序 | 源 | 备注 |
| --- | --- | --- |
| 1 | `https://mirrors.aliyun.com/pypi/simple/` | aliyun 镜像，国内最快，有完整 tensorflow 索引 |
| 2 | `https://pypi.douban.com/simple/` | 豆瓣镜像，国内备选 |
| 3 | `https://pypi.org/simple/` | PyPI 官方源，依赖 dockerfile 顶部设置的 `http_proxy=http://127.0.0.1:7897` 走代理可达 |

任何一个源装成功就立即停止；三个全部失败才报错退出。同时 `RUN` 显式声明
`SHELL ["/bin/bash", "-c"]`，因为里面用了 `local`（dash 不支持）。

#### 不想用代理 / 不想走 PyPI 源

如果你的网络访问 `pypi.org` 不稳，又不愿配代理，可以：

1. **降到 TF 2.13.1**（清华源覆盖到的最新版本）：
   ```dockerfile
   TF_PIN="tensorflow==2.13.*"
   ```
   缺点：2.13 的 keras 与 tf-addons 兼容性更脆弱，且后续打补丁很难拿到 wheel。

2. **离线 wheel**：在能联外网的机器上 `pip download tensorflow==2.15.* -d ./tf_wheels`，
   把 `tf_wheels/` `COPY` 到镜像里再 `pip install --no-index --find-links=...`。

3. **自建 PyPI 镜像**（devpi / bandersnatch），同步全量 tensorflow。

#### 想换更新的 TF 版本

`build_docker_modern.sh` 没有专门的 build-arg 控制 TF 版本，直接改
dockerfile 里的 `TF_PIN`。注意 protobuf / CUDA 兼容矩阵（参见 Q13 表格）：
在 CUDA 11.8 (u20) 上，**TF 2.15 是上限**——再新就要 CUDA 12，也就是切到
u22 镜像。

### Q16: 容器内 `./apollo.sh config` 报 `Could not find any NvInferVersion.h ... Cannot validate_cuda_config non-interactively. Aborting`

完整报错：
```
Could not find any NvInferVersion.h matching version '' in any subdirectory:
        ''
        'include'
        'include/cuda'
        'include/*-linux-gnu'
        ...
[INFO] Asking for detailed CUDA configuration...
[ERROR] Cannot validate_cuda_config non-interactively. Aborting ...
```

#### 根因：dev 阶段强制要 TensorRT，但镜像没装

`./apollo.sh config` 调 `tools/bootstrap.py`，里面有这么一段
（bootstrap.py:1202）——**只要 `stage=dev` 且 `TF_NEED_CUDA=1`，就强制
`TF_NEED_TENSORRT=1`**：
```python
if _APOLLO_DOCKER_STAGE == "dev":
    if strtobool(environ_cp.get('TF_NEED_CUDA', 'False')):
        environ_cp['TF_NEED_TENSORRT'] = '1'
        write_to_bazelrc('build:gpu --config=tensorrt')
```
`stage=dev` 来自 dev dockerfile 写入的 `/etc/apollo.conf`，必然命中。于是
`validate_cuda_config` 会把 `tensorrt` 加进必须探测的库列表，调
`third_party/gpus/find_cuda_config.py` 去找 `NvInferVersion.h` + `libnvinfer.so`。

而 config 走的是**非交互**路径（`setup_cuda_family_config_non_interactively`），
它一旦探测失败就直接 `sys.exit(1)`——不像交互模式还会循环问你要路径。

最关键的：base image `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu20.04` **只带
CUDA + cuDNN，不带 TensorRT**（TRT 是单独的 `libnvinfer*` 包）；而原来这套
modern installer **从没装过 TensorRT**。所以 `NvInferVersion.h` 必然找不到，
`config` 直接 abort。报错里 `matching version ''` 的空串也印证：非交互路径
没人给 `TF_TENSORRT_VERSION` 赋默认值。

> 这跟 Q12(bvar)/Q14(libtorch_gpu) 同源——都是"18.04 官方流水线里隐含、
> u20 重写时漏装"的依赖。

#### 修复（已应用）：新增 `installers/install_tensorrt.sh`——直接下载 `.deb` 解压，**不走 apt**

**为什么不能用 `apt install`**：NVIDIA 的 CUDA apt 源现在同时提供 TensorRT
8.x 和 10.x，每个又各有 `+cuda11.8` / `+cuda12.x` 多个 build。即便你把
`libnvinfer-dev=8.6.1.6-1+cuda11.8` 精确 pin，apt 的依赖求解器仍然会把
**传递依赖**解析成 cu12.0 / TRT10，反复 `held broken packages`：

```
libnvinfer-dev : Depends: libnvinfer-headers-dev (= 8.6.1.6-1+cuda11.8)
                          but 10.13.0.35-1+cuda12.9 is to be installed
                 Depends: libnvinfer8 (= 8.6.1.6-1+cuda11.8)
                          but 8.6.1.6-1+cuda12.0 is to be installed
```
（同一个 `8.6.1.6` 版本号下，cu11.8 和 cu12.0 两个 deb 同时存在，apt 总偏向
cu12.0；headers 拆分包 `libnvinfer-headers-dev` 又默认取最新的 TRT10。怎么
pin 都摁不住。）

**解法（与 `bvar` 同款）**：脚本直接从 NVIDIA **公开 CDN pool**
（`developer.download.nvidia.cn/compute/cuda/repos/ubuntu2004/x86_64/`，
**无需账号 / 登录**，就是 apt 源背后的同一批文件）用 `curl` 下载我们**自己
点名**的那一组 cu11.8 `.deb`，再 `dpkg-deb -x <deb> /` 解压到根。这样
**完全绕开 apt/dpkg 的依赖求解**——版本由我们自己定死，没有任何"resolve"
环节，自然不会被换成 cu12/TRT10。

下载并解压的精确包集合（全部 `8.6.1.6-1+cuda11.8`）：
```
libnvinfer8                     libnvinfer-dev        libnvinfer-headers-dev
libnvinfer-plugin8              libnvinfer-plugin-dev libnvinfer-headers-plugin-dev
libnvonnxparsers8               libnvonnxparsers-dev
```
> 关键：上一版漏了 `libnvinfer-headers-dev` / `libnvinfer-headers-plugin-dev`
> 这两个 TRT8.5+ 拆出来的头文件包——正是它们被 apt 解析成 TRT10 才报错的。
> 现在显式列进下载清单。`libnvparsers*` 仍然不要（TRT10 已删，onnxparsers 替代）。

解压后布局正好是 `find_cuda_config.py` 要的：头文件
`/usr/include/x86_64-linux-gnu/NvInfer*.h`、库
`/usr/lib/x86_64-linux-gnu/libnvinfer.so*`，最后 `ldconfig` 注册。
脚本**幂等**（检测到已装直接跳过）。

可调环境变量：
- `TRT_VERSION`（默认 `8.6.1.6`）；
- `TRT_CUDA_TAG`（默认按 `CUDA_VERSION` 推断，u20 → `cuda11.8`）；
- `TRT_DEB_BASEURL`（覆盖 deb pool 地址，比如换成 `developer.download.nvidia.com`
  或你的内网镜像）；
- `SKIP_TENSORRT=1`（整段跳过）。

`install_gpu_support.sh` 已在 `install_libtorch.sh` 之后调用它，重建 dev 镜像
即可。重建后再进容器跑 `./apollo.sh config` 就能看到：
```
[INFO] Found CUDA 11.8 in: ...
[INFO] Found cuDNN 8 in: ...
[INFO] Found TensorRT 8 in:
       /usr/lib/x86_64-linux-gnu
       /usr/include/x86_64-linux-gnu
```

容器内手动给已有镜像打补丁（不重建）：
```bash
bash /opt/apollo/installers/install_tensorrt.sh
# 期望: [ OK ] Successfully installed TensorRT 8.6.1
./apollo.sh config
```

#### 不想装 TensorRT（CPU-only 或只编 planning）

planning 模块本身不依赖 TensorRT，两种绕过方式：

1. **构建期跳过**：`SKIP_TENSORRT=1`（`install_tensorrt.sh` 会直接退出），
   但这样 `config` 仍会因为 dev 阶段强制 TRT 而失败——必须同时在 config
   时关掉 TRT 需求：
   ```bash
   # 容器内
   TF_NEED_TENSORRT=0 ./apollo.sh config   # 或 TF_NEED_CUDA=0 走 CPU
   ./apollo.sh build_cpu planning
   ```
2. **就是要 GPU+TRT 的完整能力**（perception 等需要）：用默认流程重建镜像，
   让 `install_tensorrt.sh` 把 TRT 装上即可，`config` 不用加任何环境变量。

#### CDN 下载失败 / 想换源

- 用 `TRT_DEB_BASEURL` 指向别的镜像（如把 `.cn` 换成 `.com`，或内网缓存）；
- 或在能联网的机器上把那 8 个 `.deb` 提前下好，`COPY` 进镜像后改脚本走本地路径；
- 实在不行也可以从 <https://developer.nvidia.com/tensorrt> 下 TRT8.6 的 **tar 包**，
  把 `include/` 解到 `/usr/include/x86_64-linux-gnu/`、`lib/` 解到
  `/usr/lib/x86_64-linux-gnu/` 再 `ldconfig`（与上面解 deb 等价，只是 tar 包需登录）。

## 后续可改进

- 抽取一个"瘦身 dev 镜像"，仅安装 cyber + dreamview，不装完整 perception
  深度学习栈，体积可从 ~25 GB 降到 ~6 GB。
- 增加 `aarch64` 变体（如 Jetson Orin），需要把 base image 替换为
  `nvcr.io/nvidia/l4t-cuda:11.4.x-devel-ubuntu20.04`，且 deadsnakes 的 PPA
  在 arm64 上不可用，需改成本地源码编译 python3.10。