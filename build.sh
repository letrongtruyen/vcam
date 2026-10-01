#!/bin/bash
set -eu

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$PROJECT_ROOT/layout/Applications/VCamApp.app"

mkdir -p "$APP_DIR"
mkdir -p "$PROJECT_ROOT/packages"

# 1. Tạo Info.plist cho App SwiftUI
cat > "$APP_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vcam.ios.app</string>
    <key>CFBundleName</key>
    <string>VCamApp</string>
    <key>CFBundleExecutable</key>
    <string>VCamApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>VCam cần quyền truy cập thư viện để chọn ảnh và video.</string>
</dict>
</plist>
PLIST

# 2. Biên dịch ContentView.swift thành file thực thi iOS
if command -v swiftc >/dev/null 2>&1 && command -v xcrun >/dev/null 2>&1; then
    SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
    swiftc -target arm64-apple-ios16.0 -sdk "$SDK_PATH" -parse-as-library "$PROJECT_ROOT/ContentView.swift" -o "$APP_DIR/VCamApp"
    echo "[1/2] Đã biên dịch App SwiftUI thành công."
else
    echo "Bỏ qua build App (Cần macOS/Xcode để chạy swiftc/xcrun)"
fi

# 3. Đóng gói Theos Tweak
if [ -n "${THEOS:-}" ] && [ -d "$THEOS" ]; then
    export PATH="$THEOS/bin:$PATH"
    if command -v make >/dev/null 2>&1; then
        make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
        echo "[2/2] Đã đóng gói .deb thành công!"
    else
        echo "make không tồn tại trong PATH. Cần môi trường Theos trên macOS."
        exit 1
    fi
else
    echo "THEOS chưa được thiết lập, bỏ qua package .deb."
    exit 1
fi