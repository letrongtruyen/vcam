$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Join-Path $ProjectRoot 'layout/Applications/VCamApp.app'
$PackagesDir = Join-Path $ProjectRoot 'packages'

New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
New-Item -ItemType Directory -Path $PackagesDir -Force | Out-Null

$InfoPlist = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vcam.ios.app</string>
    <key>CFBundleName</key>
    <string>VCamApp</string>
    <key>CFBundleDisplayName</key>
    <string>VCamApp</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>
</dict>
</plist>
'@

Set-Content -Path (Join-Path $AppDir 'Info.plist') -Value $InfoPlist -Encoding UTF8

Write-Host "[1/3] Created application bundle layout at $AppDir"

Write-Host "[2/3] Building app bundle with Xcode."
$xcodebuild = Get-Command xcodebuild -ErrorAction SilentlyContinue
if ($xcodebuild) {
    if (Test-Path (Join-Path $ProjectRoot 'VCamApp.xcodeproj')) {
        & xcodebuild -project (Join-Path $ProjectRoot 'VCamApp.xcodeproj') -scheme VCamApp -configuration Release -sdk iphoneos -derivedDataPath (Join-Path $ProjectRoot 'build') CODE_SIGNING_ALLOWED=NO
        if ($LASTEXITCODE -ne 0) {
            throw "Xcode build failed. Review the project configuration."
        }

        $BuildAppPath = Join-Path $ProjectRoot 'build/Build/Products/Release-iphoneos/VCamApp.app'
        if (Test-Path $BuildAppPath) {
            Copy-Item -Path $BuildAppPath -Destination $AppDir -Recurse -Force
        }
    }
    else {
        Write-Host "No Xcode project found. Create VCamApp.xcodeproj and add ContentView.swift to the app target."
        Write-Host "Example: xcodebuild -project VCamApp.xcodeproj -scheme VCamApp -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build"
    }
}
else {
    Write-Host "xcodebuild not found in PATH. The app bundle layout was still created under layout/Applications/VCamApp.app"
    Write-Host "Please run this on a macOS machine with Xcode installed."
}

Write-Host "[3/3] Packaging tweak with Theos."
$make = Get-Command make -ErrorAction SilentlyContinue
if ($make) {
    & make clean 2>$null
    & make package FINALPACKAGE=1
    if (Test-Path $PackagesDir) {
        Write-Host "Package output is in $PackagesDir"
    }
}
else {
    Write-Host "make not found. Install Theos on a macOS/iOS toolchain machine, then run:"
    Write-Host "make package FINALPACKAGE=1"
}
