# PJSIP (pjproject 2.16) iOS XCFramework Build Script

This repository provides a bash script to build **PJSIP (pjproject 2.16)** into a single **iOS XCFramework** that includes:

- **iOS Device** (arm64)
- **iOS Simulator** (arm64 on Apple Silicon, x86_64 on Intel)

> ⚠️ This repo does **NOT** include pjproject sources. You must download **pjproject 2.16** separately (pjproject has its own license).

---

## Requirements

- macOS
- Xcode installed (App Store version is fine)
- Xcode Command Line Tools

Check:
```bash
xcode-select -p
xcodebuild -version
```

---

## How to use (Step by step)

### 1) Download and extract pjproject 2.16

You should have a folder like this:

```text
pjproject-2.16/
  configure-iphone
  build/
  ...
```

### 2) Copy the script into the pjproject-2.16 folder

Place the script **directly inside** the `pjproject-2.16` directory:

```text
pjproject-2.16/
  build_pjsip_xcframework.sh   <-- put the script here
  configure-iphone
  build/
  ...
```

### 3) Make the script executable

```bash
cd /path/to/pjproject-2.16
chmod +x build_pjsip_xcframework.sh
```

### 4) Build the XCFramework

```bash
./build_pjsip_xcframework.sh
```

---

## Output

If the build succeeds, the XCFramework will be generated here:

```text
./.build/pjsip-ios/out/PJSIP.xcframework
```

Logs:

```text
./.build/pjsip-ios/out/device_config.log
./.build/pjsip-ios/out/sim_config.log
./.build/pjsip-ios/out/video_verify.log
```

---

## Optional Environment Variables

### Minimum iOS version
```bash
MIN_IOS_DEVICE=13.0 MIN_IOS_SIM=13.0 ./build_pjsip_xcframework.sh
```

### Force simulator architecture (useful on Intel Macs / CI)
```bash
ARCH_SIM=x86_64 ./build_pjsip_xcframework.sh
```

### Use a different Xcode path (e.g. Xcode Beta)
```bash
XCODE_APP=/Applications/Xcode-beta.app ./build_pjsip_xcframework.sh
```

---

## Notes

- The script copies pjproject into `./.build/` before building, so your source folder stays clean.
- It enables video flags via `pj/config_site.h` and verifies that `videodev` libraries exist.
- pjproject is a separate project and is not included here.

---

## License

This repository (script + docs) is licensed under **MIT**.

pjproject is a separate project and is distributed under its own license.
