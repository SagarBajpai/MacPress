#!/usr/bin/env bash
set -euo pipefail

app_directory="${1:?Pass the .app path}"
identity="${2:--}"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_dir="$project_root/ThirdParty/FFmpeg"
bin_directory="$app_directory/Contents/Resources/bin"
framework_directory="$app_directory/Contents/Frameworks"
license_directory="$app_directory/Contents/Resources/FFmpeg"

for name in ffmpeg ffprobe; do
    [[ -x "$vendor_dir/bin/$name" ]] || { echo "Missing $vendor_dir/bin/$name; run scripts/build-ffmpeg.sh" >&2; exit 1; }
done
[[ -f "$vendor_dir/source/ffmpeg-9.0.2.tar.xz" ]] || { echo "Missing FFmpeg source archive." >&2; exit 1; }
[[ -f "$vendor_dir/COPYING.LGPLv2.1" && -f "$vendor_dir/LICENSE.md" ]] || {
    echo "Missing FFmpeg license files; run scripts/build-ffmpeg.sh" >&2; exit 1;
}

mkdir -p "$bin_directory" "$framework_directory" "$license_directory/source"
for name in ffmpeg ffprobe; do
    ditto "$vendor_dir/bin/$name" "$bin_directory/$name"
done
for dylib in "$vendor_dir"/lib/*.dylib; do
    [[ -f "$dylib" ]] || { echo "Missing FFmpeg shared libraries." >&2; exit 1; }
    ditto "$dylib" "$framework_directory/$(basename "$dylib")"
done
for document in NOTICE.md COPYING.LGPLv2.1 LICENSE.md; do
    ditto "$vendor_dir/$document" "$license_directory/$document"
done
ditto "$vendor_dir/source/ffmpeg-9.0.2.tar.xz" "$license_directory/source/ffmpeg-9.0.2.tar.xz"

signing_options=(--force --sign "$identity" --options runtime)
if [[ "$identity" != "-" ]]; then signing_options+=(--timestamp); fi
for dylib in "$framework_directory"/*.dylib; do
    codesign "${signing_options[@]}" "$dylib"
done
for name in ffmpeg ffprobe; do
    codesign "${signing_options[@]}" --entitlements "$project_root/Resources/FFmpegTools.entitlements" "$bin_directory/$name"
done
