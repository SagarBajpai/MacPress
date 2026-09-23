#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$project_root/ThirdParty/FFmpeg/source/ffmpeg-9.0.2.tar.xz"
expected_sha256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
build_root="$project_root/.build/ffmpeg-redistributable"
source_dir="$build_root/ffmpeg-9.0.2"
vendor_dir="$project_root/ThirdParty/FFmpeg"

[[ "$(uname -m)" == "arm64" ]] || { echo "An Apple Silicon Mac is required." >&2; exit 1; }
[[ -f "$archive" ]] || { echo "Missing FFmpeg source archive: $archive" >&2; exit 1; }
actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual_sha256" == "$expected_sha256" ]] || { echo "FFmpeg source checksum mismatch." >&2; exit 1; }

mkdir -p "$build_root"
if [[ ! -f "$source_dir/configure" ]]; then
    tar -xf "$archive" -C "$build_root"
fi
cd "$source_dir"
if [[ ! -f ffbuild/config.mak ]]; then
    ./configure \
        --arch=arm64 --target-os=darwin --cc=/usr/bin/clang \
        --extra-cflags='-mmacosx-version-min=14.0 -arch arm64' \
        --extra-ldflags='-mmacosx-version-min=14.0 -arch arm64' \
        --extra-ldexeflags='-Wl,-rpath,@executable_path/../../Frameworks' \
        --extra-ldsoflags='-Wl,-rpath,@loader_path' \
        --disable-autodetect --disable-doc --disable-debug --disable-ffplay \
        --disable-network --enable-small --enable-videotoolbox --enable-audiotoolbox \
        --enable-shared --disable-static --disable-gpl --disable-nonfree \
        --install-name-dir='@rpath'
fi
make -j8 ffmpeg ffprobe

mkdir -p "$vendor_dir/bin" "$vendor_dir/lib"
ditto ffmpeg "$vendor_dir/bin/ffmpeg"
ditto ffprobe "$vendor_dir/bin/ffprobe"
for component in avcodec avformat avutil avfilter avdevice swscale swresample; do
    dylib="$(find "$source_dir/lib$component" -maxdepth 1 -type f -name "lib$component.*.dylib" -print -quit)"
    [[ -n "$dylib" ]] || { echo "Missing lib$component dylib." >&2; exit 1; }
    ditto "$dylib" "$vendor_dir/lib/$(basename "$dylib")"
done
ditto "$source_dir/COPYING.LGPLv2.1" "$vendor_dir/COPYING.LGPLv2.1"
ditto "$source_dir/LICENSE.md" "$vendor_dir/LICENSE.md"
"$project_root/scripts/verify-ffmpeg-bundle.sh" "$vendor_dir"
printf 'Prepared redistributable FFmpeg in %s\n' "$vendor_dir"
