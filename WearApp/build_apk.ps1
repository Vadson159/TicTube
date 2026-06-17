$ErrorActionPreference = "Stop"

$ProjectDir = $PSScriptRoot
$SdkDir = Join-Path $ProjectDir "android-sdk"
$JdkDir = Join-Path $ProjectDir "jdk"

Write-Host "========================================="
Write-Host "TicTube Wear OS - Zero-to-APK Build Setup"
Write-Host "========================================="

# 1. Download and Extract JDK (Adoptium 17)
if (-not (Test-Path $JdkDir)) {
    Write-Host "`n[1/4] Downloading JDK 17 (Adoptium)..."
    $JdkUrl = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.zip"
    $JdkZip = Join-Path $ProjectDir "jdk.zip"
    Invoke-WebRequest -Uri $JdkUrl -OutFile $JdkZip
    
    Write-Host "Extracting JDK..."
    Expand-Archive -Path $JdkZip -DestinationPath $ProjectDir
    Rename-Item -Path (Join-Path $ProjectDir "jdk-17.0.11+9") -NewName "jdk"
    Remove-Item $JdkZip
    Write-Host "JDK 17 setup complete."
} else {
    Write-Host "`n[1/4] JDK 17 already exists."
}

$env:JAVA_HOME = $JdkDir
$env:PATH = "$JdkDir\bin;" + $env:PATH

# 2. Download and Extract Android Command Line Tools
if (-not (Test-Path $SdkDir)) {
    Write-Host "`n[2/4] Downloading Android Command Line Tools..."
    # URL for Windows cmdline-tools
    $CmdLineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    $CmdLineToolsZip = Join-Path $ProjectDir "cmdline-tools.zip"
    Invoke-WebRequest -Uri $CmdLineToolsUrl -OutFile $CmdLineToolsZip
    
    $CmdLineToolsTemp = Join-Path $ProjectDir "cmdline-tools-temp"
    Write-Host "Extracting Android Command Line Tools..."
    Expand-Archive -Path $CmdLineToolsZip -DestinationPath $CmdLineToolsTemp
    
    $LatestDir = Join-Path $SdkDir "cmdline-tools\latest"
    New-Item -ItemType Directory -Force -Path $LatestDir | Out-Null
    Copy-Item -Path "$CmdLineToolsTemp\cmdline-tools\*" -Destination $LatestDir -Recurse
    Remove-Item $CmdLineToolsTemp -Recurse -Force
    Remove-Item $CmdLineToolsZip
    Write-Host "Android Command Line Tools setup complete."
} else {
    Write-Host "`n[2/4] Android SDK already exists."
}

$env:ANDROID_HOME = $SdkDir
$SdkManager = Join-Path $SdkDir "cmdline-tools\latest\bin\sdkmanager.bat"

# 3. Accept Licenses and install required SDK packages
Write-Host "`n[3/4] Accepting Android SDK licenses and installing required packages (platforms, build-tools)..."
cmd.exe /c "echo y| `"$SdkManager`" --licenses > NUL"
cmd.exe /c "`"$SdkManager`" `"platforms;android-34`" `"build-tools;34.0.0`""

# 4. Setup Gradle Wrapper and Build
Write-Host "`n[4/4] Setting up Gradle and building APK..."
Set-Location $ProjectDir

if (-not (Test-Path (Join-Path $ProjectDir "gradlew.bat"))) {
    Write-Host "Downloading Gradle distribution to initialize wrapper..."
    $GradleVersion = "8.7"
    $GradleUrl = "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip"
    $GradleZip = Join-Path $ProjectDir "gradle.zip"
    Invoke-WebRequest -Uri $GradleUrl -OutFile $GradleZip
    Expand-Archive -Path $GradleZip -DestinationPath $ProjectDir
    
    $GradleBin = Join-Path $ProjectDir "gradle-$GradleVersion\bin\gradle.bat"
    cmd.exe /c "`"$GradleBin`" wrapper"
    
    Remove-Item $GradleZip
    Remove-Item -Path (Join-Path $ProjectDir "gradle-$GradleVersion") -Recurse -Force
}

Write-Host "Building project with Gradle Wrapper..."
cmd.exe /c "gradlew.bat assembleDebug"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n========================================="
    Write-Host "BUILD SUCCESSFUL! 🎉"
    Write-Host "APK Location: $(Join-Path $ProjectDir "app\build\outputs\apk\debug\app-debug.apk")"
    Write-Host "========================================="
} else {
    Write-Host "`n========================================="
    Write-Host "BUILD FAILED. Please check the logs above."
    Write-Host "========================================="
}
