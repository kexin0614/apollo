"""Loads the ffmpeg library"""

# Sanitize a dependency so that it works correctly from code that includes
# Apollo as a submodule.
def clean_dep(dep):
    return str(Label(dep))

def repo():
    # NOTE(apollo-modern-image): point @ffmpeg at the distro's apt-installed
    # ffmpeg headers instead of Apollo's prebuilt (bionic) sysroot copy. On
    # focal/jammy the libav* headers live under the multiarch include dir, and
    # the matching libav*.so / libx264.so etc. come from the distro packages —
    # so we no longer need the bionic libx264.so.155 / libx265.so.179 shims.
    # See README_modern.md Q19.
    native.new_local_repository(
        name = "ffmpeg",
        build_file = clean_dep("//third_party/ffmpeg:ffmpeg.BUILD"),
        path = "/usr/include/x86_64-linux-gnu",
    )
