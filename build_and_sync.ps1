# PDF Project - Build & Sync Script
# This script builds the latest APK and syncs it with the landing page downloads.

Write-Host "Starting Build Process..." -ForegroundColor Cyan

# Use absolute path to flutter if not in PATH
$FLUTTER_BIN = "C:\Users\jonat\Downloads\flutter_windows_3.41.2-stable\flutter\bin\flutter.bat"
if (-not (Test-Path $FLUTTER_BIN)) {
    $FLUTTER_BIN = "flutter" # Fallback to PATH
}

# 1. Clean and Build APK
Write-Host "Building Release APK with Split-ABI (this may take a few minutes)..." -ForegroundColor Yellow
$BuildOutput = & $FLUTTER_BIN build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols --split-per-abi 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    Write-Host $BuildOutput
    exit $LASTEXITCODE
}

# 2. Ensure Latest_Builds directory exists
if (-not (Test-Path "Latest_Builds")) {
    New-Item -ItemType Directory -Path "Latest_Builds"
}

# 3. Find the built APK (preferring arm64-v8a for size/compatibility)
Write-Host "Searching for built APK..." -ForegroundColor Yellow
$PossiblePaths = @(
    "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk",
    "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk",
    "build/app/outputs/flutter-apk/app-release.apk"
)

$FoundApk = $null
foreach ($Path in $PossiblePaths) {
    if (Test-Path $Path) {
        $FoundApk = $Path
        break
    }
}

if ($null -eq $FoundApk) {
    Write-Host "Could not find a suitable APK in build/app/outputs/flutter-apk/!" -ForegroundColor Red
    exit 1
}

# 4. Copy APK to sync folder
Write-Host "Syncing $FoundApk to Latest_Builds..." -ForegroundColor Yellow
Copy-Item $FoundApk "Latest_Builds/PDF_Scanner_Latest.apk" -Force

Write-Host "Success! Latest build is now available at Latest_Builds/PDF_Scanner_Latest.apk" -ForegroundColor Green
Write-Host "The landing page is now pointing to this latest version." -ForegroundColor Green
