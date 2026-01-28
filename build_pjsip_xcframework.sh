#!/usr/bin/env bash
set -euo pipefail

# Build PJSIP (pjproject) as a single XCFramework (device + simulator)
#
# Usage:
#   cd /path/to/pjproject
#   chmod +x scripts/build_pjsip_xcframework.sh
#   ./scripts/build_pjsip_xcframework.sh
#
# Output:
#   ./.build/pjsip-ios/out/PJSIP.xcframework
#
# Env overrides:
#   MIN_IOS_DEVICE=13.0
#   MIN_IOS_SIM=13.0
#   ARCH_DEVICE=arm64
#   ARCH_SIM=arm64|x86_64
#   XCODE_APP=/Applications/Xcode.app

MIN_IOS_DEVICE="${MIN_IOS_DEVICE:-13.0}"
MIN_IOS_SIM="${MIN_IOS_SIM:-13.0}"
ARCH_DEVICE="${ARCH_DEVICE:-arm64}"
XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"

SIM_DEVPATH="$XCODE_APP/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer"

# Resolve script dir & pjproject root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR"
cd "$SRC_DIR"

# Auto-pick simulator arch if not set explicitly
if [[ -z "${ARCH_SIM:-}" ]]; then
  HOST_ARCH="$(uname -m)"
  if [[ "$HOST_ARCH" == "arm64" ]]; then
    ARCH_SIM="arm64"
  else
    ARCH_SIM="x86_64"
  fi
fi

ROOT_DIR="$SRC_DIR/.build/pjsip-ios"
WORK_DIR="$ROOT_DIR/work"
OUT_DIR="$ROOT_DIR/out"

DEVICE_DIR="$WORK_DIR/pjproject-device"
SIM_DIR="$WORK_DIR/pjproject-sim"

die() { echo "ERROR: $*" >&2; exit 1; }

echo "==> pjproject root : $SRC_DIR"
echo "==> build root     : $ROOT_DIR"
echo "==> out dir        : $OUT_DIR"

[[ -f "$SRC_DIR/configure-iphone" ]] || die "configure-iphone not found. Run this script from a pjproject source tree (pjproject root)."
[[ -f "$SRC_DIR/build/os-auto.mak.in" ]] || die "Missing build/os-auto.mak.in. Source tree looks incomplete."
[[ -d "$SIM_DEVPATH" ]] || die "Simulator DEVPATH not found: $SIM_DEVPATH (set XCODE_APP=/path/to/Xcode.app)"

# Safety guard before deleting anything
# We only ever delete inside pjproject/.build/
[[ "$ROOT_DIR" == "$SRC_DIR/.build/"* ]] || die "Refusing to delete non-build dir: $ROOT_DIR"

rm -rf "$ROOT_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"

echo "==> Copying source into work dirs..."
cp -R "$SRC_DIR" "$DEVICE_DIR"
cp -R "$SRC_DIR" "$SIM_DIR"

# config_site.h: include sample first, then overrides
write_config_site() {
  local ROOT="$1"
  local CFG="$ROOT/pjlib/include/pj/config_site.h"
  mkdir -p "$(dirname "$CFG")"
  cat > "$CFG" <<'EOF'
#define PJ_CONFIG_IPHONE 1
#include <pj/config_site_sample.h>

/* ---- VIDEO ENABLE ---- */
#define PJMEDIA_HAS_VIDEO 1
#define PJMEDIA_HAS_VID_DEV 1
#define PJMEDIA_HAS_VID_TOOLBOX_CODEC 1
EOF
}

write_config_site "$DEVICE_DIR"
write_config_site "$SIM_DIR"

# Clean (IMPORTANT: DO NOT delete build/ directory)
pj_clean() {
  local ROOT="$1"
  (cd "$ROOT" && \
    make distclean 2>/dev/null || true; \
    rm -f build.mak; \
    rm -rf pjlib/lib pjlib-util/lib pjnath/lib pjmedia/lib pjsip/lib third_party/lib \
  )
  [[ -f "$ROOT/build/os-auto.mak.in" ]] || die "build/os-auto.mak.in missing after clean (DO NOT delete build/)."
}

echo "==> BUILD DEVICE (arch=$ARCH_DEVICE min_iOS=$MIN_IOS_DEVICE)"
pj_clean "$DEVICE_DIR"
(
  cd "$DEVICE_DIR"
  unset DEVPATH
  export ARCH="-arch $ARCH_DEVICE"
  export MIN_IOS="-miphoneos-version-min=$MIN_IOS_DEVICE"

  # Try with --enable-video, fallback if unsupported
  ./configure-iphone --enable-video 2>&1 | tee "$OUT_DIR/device_config.log" || \
  ./configure-iphone 2>&1 | tee -a "$OUT_DIR/device_config.log"

  [[ -f build/host-unix.mak ]] || die "Device configure failed. See $OUT_DIR/device_config.log"
  make dep && make clean && make
)

echo "==> BUILD SIMULATOR (arch=$ARCH_SIM min_iOS=$MIN_IOS_SIM)"
pj_clean "$SIM_DIR"
(
  cd "$SIM_DIR"
  export DEVPATH="$SIM_DEVPATH"
  export ARCH="-arch $ARCH_SIM"
  export CFLAGS="-O2 -m64"
  export LDFLAGS="-O2 -m64"
  export MIN_IOS="-mios-simulator-version-min=$MIN_IOS_SIM"

  # Try with --enable-video, fallback if unsupported
  ./configure-iphone --enable-video 2>&1 | tee "$OUT_DIR/sim_config.log" || \
  ./configure-iphone 2>&1 | tee -a "$OUT_DIR/sim_config.log"

  [[ -f build/host-unix.mak ]] || die "Sim configure failed. See $OUT_DIR/sim_config.log"
  make dep && make clean && make
)

make_umbrella() {
  local ROOT="$1"
  local OUT_A="$2"

  local LIB_DIRS=(
    "$ROOT/pjlib/lib"
    "$ROOT/pjlib-util/lib"
    "$ROOT/pjnath/lib"
    "$ROOT/pjmedia/lib"
    "$ROOT/pjsip/lib"
    "$ROOT/third_party/lib"
  )

  local LIBS=()
  for d in "${LIB_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
      while IFS= read -r -d '' f; do
        LIBS+=("$f")
      done < <(find "$d" -maxdepth 1 -name "*.a" -print0)
    fi
  done

  [[ "${#LIBS[@]}" -gt 0 ]] || die "No .a files found under $ROOT"
  /usr/bin/libtool -static -o "$OUT_A" "${LIBS[@]}"
}

DEVICE_UMBRELLA="$OUT_DIR/libpjsip-all-device.a"
SIM_UMBRELLA="$OUT_DIR/libpjsip-all-sim.a"

echo "==> Creating umbrella libs..."
make_umbrella "$DEVICE_DIR" "$DEVICE_UMBRELLA"
make_umbrella "$SIM_DIR" "$SIM_UMBRELLA"

# Verify video artifacts (log to file)
echo "==> Verifying video build artifacts..." | tee -a "$OUT_DIR/video_verify.log"

if compgen -G "$DEVICE_DIR/pjmedia/lib/*videodev*.a" > /dev/null; then
  echo "✅ Device: videodev static lib found" | tee -a "$OUT_DIR/video_verify.log"
else
  echo "❌ Device: videodev static lib MISSING" | tee -a "$OUT_DIR/video_verify.log"
  exit 1
fi

if compgen -G "$SIM_DIR/pjmedia/lib/*videodev*.a" > /dev/null; then
  echo "✅ Simulator: videodev static lib found" | tee -a "$OUT_DIR/video_verify.log"
else
  echo "❌ Simulator: videodev static lib MISSING" | tee -a "$OUT_DIR/video_verify.log"
  exit 1
fi

HDR_DIR="$OUT_DIR/Headers"
mkdir -p "$HDR_DIR"
rsync -a "$DEVICE_DIR/pjlib/include/" "$HDR_DIR/"
rsync -a "$DEVICE_DIR/pjlib-util/include/" "$HDR_DIR/"
rsync -a "$DEVICE_DIR/pjnath/include/" "$HDR_DIR/"
rsync -a "$DEVICE_DIR/pjmedia/include/" "$HDR_DIR/"
rsync -a "$DEVICE_DIR/pjsip/include/" "$HDR_DIR/"

XC_OUT="$OUT_DIR/PJSIP.xcframework"
rm -rf "$XC_OUT"

echo "==> Creating XCFramework..."
xcodebuild -create-xcframework \
  -library "$DEVICE_UMBRELLA" -headers "$HDR_DIR" \
  -library "$SIM_UMBRELLA" -headers "$HDR_DIR" \
  -output "$XC_OUT"

echo ""
echo "✅ DONE"
echo "Output: $XC_OUT"
echo "Logs  : $OUT_DIR/device_config.log, $OUT_DIR/sim_config.log"
echo "Video : $OUT_DIR/video_verify.log"
