# FFmpeg redistribution notice

Screen Compressor bundles unmodified FFmpeg 9.0.2 command-line tools and their
shared libraries. FFmpeg is a separate project and is not affiliated with Screen
Compressor. The bundled FFmpeg build is licensed under the GNU Lesser General
Public License, version 2.1 or later (LGPL-2.1-or-later). Its license text and
upstream license notes are included alongside this notice. The complete
corresponding FFmpeg source is provided in `source/ffmpeg-9.0.2.tar.xz`.

The bundled tools were configured without `--enable-gpl`, `--enable-nonfree`,
external codec libraries, or Homebrew libraries. FFmpeg's own build reports
"License: LGPL version 2.1 or later". Apple VideoToolbox and AudioToolbox are
the only enabled external acceleration libraries. The shared FFmpeg libraries
are independently replaceable in `Contents/Frameworks`; the release signing
entitlement for the FFmpeg tools disables library validation to allow lawful
replacement of those LGPL libraries.

Replacing a library changes the app bundle's code seal, so a modified personal
copy must be re-signed locally before macOS will run it. Re-signing that copy
does not preserve the distributor's notarization. These signing details do not
restrict modification or redistribution under the applicable FFmpeg license.

The FFmpeg source includes Independent JPEG Group (IJG) material in
`libavcodec/jfdctfst.c`, `libavcodec/jfdctint_template.c`, and
`libavcodec/jrevdct.c`. We credit the Independent JPEG Group for that work.
Screen Compressor makes no changes to those files; the exact upstream source
is included in the archive above.

Source: https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz
Source SHA-256: `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`
Upstream license guidance: https://ffmpeg.org/legal.html

HEVC/H.265 and other media formats may involve patent rights in some
jurisdictions. The LGPL copyright notice does not grant patent rights.
