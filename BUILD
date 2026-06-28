load("//tools/install:install.bzl", "install", "install_src_files")
load("//third_party/gpus:common.bzl", "if_gpu")
load("@hedron_compile_commands//:refresh_compile_commands.bzl", "refresh_compile_commands")

package(
    default_visibility = ["//visibility:public"],
)

exports_files([
    "CPPLINT.cfg",
    "tox.ini",
])

# +-------------------------------------------------------------------------+
# | refresh_compile_commands: 为 clangd 生成 compile_commands.json          |
# |                                                                         |
# | 用法:                                                                   |
# |   bazel run //:refresh_compile_commands           (CPU, 默认)          |
# |   bazel run //:refresh_compile_commands_gpu        (GPU/NVIDIA)         |
# | 或使用封装脚本:                                                         |
# |   bash scripts/gen_compile_commands.sh             (CPU, 默认)          |
# |   bash scripts/gen_compile_commands.sh --config=gpu                     |
# |                                                                         |
# | 关于 flag 一致性:                                                       |
# |   `apollo.sh build` 最终执行的命令形如:                                 |
# |     bazel build <CMDLINE_OPTIONS> <job_args> -- <targets>               |
# |   其中除 .bazelrc / tools/bazel.rc 内的全局 flag (会被 bazel run 自动   |
# |   继承) 外, 还在命令行额外注入了以下 flag, 这里逐一对齐:                |
# |     - --config=cpu / --config=gpu(+nvidia/amd)  (determine_cpu_or_gpu)  |
# |     - --define ENABLE_PROFILER=true             (默认开启)             |
# |     - --copt=-mavx2 --host_copt=-mavx2          (x86_64 的 job_args)    |
# |   注: C++ 标准 (-std=c++14) 已在 tools/bazel.rc 中定义, 无需重复添加。  |
# +-------------------------------------------------------------------------+

# 与 apollo.sh build (x86_64, CPU 模式) 对齐的编译 flag
APOLLO_CPU_BUILD_FLAGS = " ".join([
    "--config=cpu",
    "--define ENABLE_PROFILER=true",
    "--copt=-mavx2",
    "--host_copt=-mavx2",
])

# 与 apollo.sh build --config=gpu (x86_64, NVIDIA) 对齐的编译 flag
APOLLO_GPU_BUILD_FLAGS = " ".join([
    "--config=gpu",
    "--config=nvidia",
    "--define ENABLE_PROFILER=true",
    "--copt=-mavx2",
    "--host_copt=-mavx2",
])

refresh_compile_commands(
    name = "refresh_compile_commands",
    targets = {
        "//modules/...": APOLLO_CPU_BUILD_FLAGS,
        "//cyber/...": APOLLO_CPU_BUILD_FLAGS,
    },
)

refresh_compile_commands(
    name = "refresh_compile_commands_gpu",
    targets = {
        "//modules/...": APOLLO_GPU_BUILD_FLAGS,
        "//cyber/...": APOLLO_GPU_BUILD_FLAGS,
    },
)

install(
    name = "deprecated_install",
    deps = if_gpu(
        [
            "//third_party/centerpoint_infer_op:install",
            "//third_party/paddleinference:install",
            "//third_party/tf2:install",
            "//third_party/caddn_infer_op:install",
            "//third_party/absl:install",
            "//third_party/ad_rss_lib:install",
            "//third_party/boost:install",
            "//third_party/civetweb:install",
            "//third_party/eigen3:install",
            "//third_party/gtest:install",
            "//third_party/ipopt:install",
            "//third_party/libtorch:install",
            "//third_party/fastdds:install",
            "//third_party/gflags:install",
            "//third_party/glog:install",
            "//third_party/nlohmann_json:install",
            "//third_party/opencv:install",
            "//third_party/osqp:install",
            "//third_party/pcl:install",
            "//third_party/vtk:install",
            "//third_party/proj:install",
            "//third_party/protobuf:install",
            "//third_party/py:install",
            "//third_party/opengl:install",
            "//third_party/openh264:install",
            "//third_party/cpplint:install",
            "//third_party/portaudio:install",
            "//third_party/fftw3:install",
            "//third_party/glew:install",
            "//third_party/adolc:install",
            "//third_party/atlas:install",
            "//third_party/benchmark:install",
            "//third_party/ncurses5:install",
            "//third_party/sqlite3:install",
            "//third_party/tensorrt:install",
            "//third_party/tinyxml2:install",
            "//third_party/uuid:install",
            "//third_party/yaml_cpp:install",
            "//third_party/qt5:install",
            "//third_party/npp:install",
            "//third_party/camera_library:install",
            "//third_party/can_card_library:install",
            "//third_party/gpus:install",
            "//third_party/nvjpeg:install",
            "//third_party/localization_msf:install",
            "//third_party/ffmpeg:install",
            "//third_party/adv_plat:install",
            "//scripts:install",
            "//tools:install",
        ],
        [
            "//third_party/absl:install",
            "//third_party/ad_rss_lib:install",
            "//third_party/tf2:install",
            "//third_party/boost:install",
            "//third_party/civetweb:install",
            "//third_party/eigen3:install",
            "//third_party/gtest:install",
            "//third_party/ipopt:install",
            "//third_party/libtorch:install",
            "//third_party/fastdds:install",
            "//third_party/gflags:install",
            "//third_party/glog:install",
            "//third_party/nlohmann_json:install",
            "//third_party/opencv:install",
            "//third_party/osqp:install",
            "//third_party/pcl:install",
            "//third_party/vtk:install",
            "//third_party/proj:install",
            "//third_party/protobuf:install",
            "//third_party/py:install",
            "//third_party/opengl:install",
            "//third_party/openh264:install",
            "//third_party/cpplint:install",
            "//third_party/centerpoint_infer_op:install",
            "//third_party/portaudio:install",
            "//third_party/fftw3:install",
            "//third_party/glew:install",
            "//third_party/adolc:install",
            "//third_party/atlas:install",
            "//third_party/benchmark:install",
            "//third_party/camera_library:install",
            "//third_party/can_card_library:install",
            "//third_party/ncurses5:install",
            "//third_party/sqlite3:install",
            "//third_party/tensorrt:install",
            "//third_party/tinyxml2:install",
            "//third_party/uuid:install",
            "//third_party/yaml_cpp:install",
            "//third_party/qt5:install",
            "//third_party/nvjpeg:install",
            "//third_party/npp:install",
            "//third_party/gpus:install",
            "//third_party/localization_msf:install",
            "//third_party/ffmpeg:install",
            "//third_party/adv_plat:install",
            "//scripts:install",
            "//tools:install",
        ],
    ),
)

install_src_files(
    name = "deprecated_install_src",
    deps = if_gpu(
        [
            "//third_party/centerpoint_infer_op:install_src",
            "//third_party/paddleinference:install_src",
            "//third_party/caddn_infer_op:install_src",
            "//third_party/camera_library:install_src",
            "//third_party/can_card_library:install_src",
            "//third_party/tf2:install_src",
            "//third_party/absl:install_src",
            "//third_party/boost:install_src",
            "//third_party/civetweb:install_src",
            "//third_party/eigen3:install_src",
            "//third_party/gtest:install_src",
            "//third_party/ipopt:install_src",
            "//third_party/libtorch:install_src",
            "//third_party/fastdds:install_src",
            "//third_party/gflags:install_src",
            "//third_party/glog:install_src",
            "//third_party/nlohmann_json:install_src",
            "//third_party/opencv:install_src",
            "//third_party/osqp:install_src",
            "//third_party/pcl:install_src",
            "//third_party/vtk:install_src",
            "//third_party/proj:install_src",
            "//third_party/protobuf:install_src",
            "//third_party/py:install_src",
            "//third_party/opengl:install_src",
            "//third_party/openh264:install_src",
            "//third_party/cpplint:install_src",
            "//third_party/portaudio:install_src",
            "//third_party/fftw3:install_src",
            "//third_party/glew:install_src",
            "//third_party/adolc:install_src",
            "//third_party/atlas:install_src",
            "//third_party/benchmark:install_src",
            "//third_party/ncurses5:install_src",
            "//third_party/sqlite3:install_src",
            "//third_party/tensorrt:install_src",
            "//third_party/tinyxml2:install_src",
            "//third_party/uuid:install_src",
            "//third_party/yaml_cpp:install_src",
            "//third_party/qt5:install_src",
            "//third_party/npp:install_src",
            "//third_party/nvjpeg:install_src",
            "//third_party/gpus:install_src",
            "//third_party/localization_msf:install_src",
            "//third_party/ffmpeg:install_src",
            "//third_party/adv_plat:install_src",
            "//tools:install_src",
        ],
        [
            "//tools:install_src",
            "//third_party/absl:install_src",
            "//third_party/boost:install_src",
            "//third_party/civetweb:install_src",
            "//third_party/eigen3:install_src",
            "//third_party/gtest:install_src",
            "//third_party/camera_library:install_src",
            "//third_party/can_card_library:install_src",
            "//third_party/tf2:install_src",
            "//third_party/centerpoint_infer_op:install_src",
            "//third_party/ipopt:install_src",
            "//third_party/libtorch:install_src",
            "//third_party/fastdds:install_src",
            "//third_party/gflags:install_src",
            "//third_party/glog:install_src",
            "//third_party/nlohmann_json:install_src",
            "//third_party/opencv:install_src",
            "//third_party/osqp:install_src",
            "//third_party/pcl:install_src",
            "//third_party/vtk:install_src",
            "//third_party/proj:install_src",
            "//third_party/protobuf:install_src",
            "//third_party/py:install_src",
            "//third_party/opengl:install_src",
            "//third_party/openh264:install_src",
            "//third_party/cpplint:install_src",
            "//third_party/portaudio:install_src",
            "//third_party/fftw3:install_src",
            "//third_party/glew:install_src",
            "//third_party/adolc:install_src",
            "//third_party/atlas:install_src",
            "//third_party/benchmark:install_src",
            "//third_party/ncurses5:install_src",
            "//third_party/sqlite3:install_src",
            "//third_party/tensorrt:install_src",
            "//third_party/tinyxml2:install_src",
            "//third_party/uuid:install_src",
            "//third_party/yaml_cpp:install_src",
            "//third_party/qt5:install_src",
            "//third_party/npp:install_src",
            "//third_party/nvjpeg:install_src",
            "//third_party/gpus:install_src",
            "//third_party/localization_msf:install_src",
            "//third_party/ffmpeg:install_src",
            "//third_party/adv_plat:install_src",
        ],
    ),
)
