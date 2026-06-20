load("@rules_cc//cc:defs.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

# NOTE(apollo-modern-image): link against the distro's apt-installed ffmpeg
# (focal 4.2 / jammy 4.4) under /usr/lib/x86_64-linux-gnu instead of Apollo's
# prebuilt bionic sysroot copy. The distro ffmpeg links the distro's own
# libx264.so.163 / libx265.so.199, so the bionic .so.155 / .so.179 shims are
# no longer needed. See README_modern.md Q19.
cc_library(
    name = "avcodec",
    includes = ["."],
    hdrs = glob(["libavcodec/*.h"]),
    linkopts = [
        "-L/usr/lib/x86_64-linux-gnu",
        "-lavcodec",
    ],
)

cc_library(
    name = "avformat",
    includes = ["."],
    hdrs = glob(["libavformat/*.h"]),
    linkopts = [
        "-L/usr/lib/x86_64-linux-gnu",
        "-lavformat",
    ],
)

cc_library(
    name = "swscale",
    includes = ["."],
    hdrs = glob(["libswscale/*.h"]),
    linkopts = [
        "-L/usr/lib/x86_64-linux-gnu",
        "-lswscale",
    ],
)

cc_library(
    name = "avutil",
    includes = ["."],
    hdrs = glob(["libavutil/*.h"]),
    linkopts = [
        "-L/usr/lib/x86_64-linux-gnu",
        "-lavutil",
    ],
)
