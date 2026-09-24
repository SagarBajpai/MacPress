#!/usr/bin/env bash
set -euo pipefail

input="${1:?Pass a .app or ThirdParty/FFmpeg directory}"
if [[ "$input" == *.app ]]; then
    bin_directory="$input/Contents/Resources/bin"
    library_directory="$input/Contents/Frameworks"
    license_directory="$input/Contents/Resources/FFmpeg"
    app_executable="$input/Contents/MacOS/MacPress"
    [[ -x "$app_executable" ]] || { echo "Missing app executable." >&2; exit 1; }
    lipo "$app_executable" -verify_arch arm64
    run_tool() { "$bin_directory/$1" "${@:2}"; }
else
    bin_directory="$input/bin"
    library_directory="$input/lib"
    license_directory="$input"
    run_tool() { DYLD_LIBRARY_PATH="$library_directory" "$bin_directory/$1" "${@:2}"; }
fi

for name in ffmpeg ffprobe; do
    executable="$bin_directory/$name"
    [[ -x "$executable" ]] || { echo "Missing executable: $executable" >&2; exit 1; }
    lipo "$executable" -verify_arch arm64
    run_tool "$name" -version >/dev/null
done
version_info="$(run_tool ffmpeg -version)"
for flag in --disable-gpl --disable-nonfree --enable-shared --disable-static --enable-videotoolbox; do
    grep -Fq -- "$flag" <<< "$version_info" || { echo "Unexpected FFmpeg build: missing $flag" >&2; exit 1; }
done
encoders="$(run_tool ffmpeg -hide_banner -encoders 2>/dev/null)"
grep -q hevc_videotoolbox <<< "$encoders"
grep -q ' aac ' <<< "$encoders"
executables=("$bin_directory/ffmpeg" "$bin_directory/ffprobe" "$library_directory"/*.dylib)
if [[ -n "${app_executable:-}" ]]; then executables+=("$app_executable"); fi
for executable in "${executables[@]}"; do
    [[ -f "$executable" ]] || { echo "Missing library: $executable" >&2; exit 1; }
    lipo "$executable" -verify_arch arm64
    if otool -L "$executable" | grep -E '/opt/homebrew/|/usr/local/'; then
        echo "Non-system dependency in $executable" >&2
        exit 1
    fi
done
[[ -f "$license_directory/COPYING.LGPLv2.1" && -f "$license_directory/LICENSE.md" && -f "$license_directory/NOTICE.md" ]] || {
    echo "Missing FFmpeg notices." >&2; exit 1;
}
[[ -f "$license_directory/source/ffmpeg-9.0.2.tar.xz" ]] || { echo "Missing FFmpeg source." >&2; exit 1; }
source_sha256="$(shasum -a 256 "$license_directory/source/ffmpeg-9.0.2.tar.xz" | awk '{print $1}')"
[[ "$source_sha256" == "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e" ]] || {
    echo "FFmpeg source checksum mismatch." >&2; exit 1;
}
printf 'FFmpeg bundle verified: %s\n' "$input"
