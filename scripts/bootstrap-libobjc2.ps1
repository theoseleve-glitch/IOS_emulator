Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$vendorRoot = Join-Path $repoRoot 'vendor'
$sourceRoot = Join-Path $vendorRoot 'libobjc2-src'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message"
}

function Get-VisualStudioInstallPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        return $null
    }

    $path = & $vswhere -latest -products * -property installationPath
    if (-not $path) {
        return $null
    }

    return ($path | Select-Object -First 1).Trim()
}

function Resolve-NinjaPath {
    $installPath = Get-VisualStudioInstallPath
    if (-not $installPath) {
        return $null
    }

    $candidate = Join-Path $installPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
    if (Test-Path $candidate) {
        return $candidate
    }

    return $null
}

Write-Step 'Loading the Windows toolchain environment'
. (Join-Path $PSScriptRoot 'env-windows.ps1')

if (-not $Architecture) {
    $Architecture = $env:IPHONE_EMULATOR_HOST_ARCH
}
if (-not $Architecture) {
    $Architecture = 'x64'
}

$buildRoot = Join-Path $vendorRoot "libobjc2-build-$Architecture"

$git = Get-Command git -ErrorAction SilentlyContinue
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
$clang = Get-Command clang -ErrorAction SilentlyContinue
$ninja = Get-Command ninja -ErrorAction SilentlyContinue
if (-not $ninja) {
    $ninjaPath = Resolve-NinjaPath
    if ($ninjaPath) {
        $env:Path = "$(Split-Path -Parent $ninjaPath);$env:Path"
        $ninja = Get-Command ninja -ErrorAction SilentlyContinue
    }
}

foreach ($required in @(
    @{ Name = 'git'; Value = $git },
    @{ Name = 'cmake'; Value = $cmake },
    @{ Name = 'clang'; Value = $clang },
    @{ Name = 'ninja'; Value = $ninja }
)) {
    if (-not $required.Value) {
        throw "Required command '$($required.Name)' is not available. Bootstrap the Windows toolchain first."
    }
}

Write-Step 'Preparing vendor directories'
New-Item -ItemType Directory -Path $vendorRoot -Force | Out-Null

if (-not (Test-Path $sourceRoot)) {
    Write-Step 'Cloning gnustep/libobjc2'
    & git clone --depth 1 https://github.com/gnustep/libobjc2.git $sourceRoot
} else {
    Write-Step 'Refreshing existing gnustep/libobjc2 checkout'
    & git -C $sourceRoot pull --ff-only
}

Write-Step 'Configuring libobjc2 with CMake + Ninja'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
& cmake -S $sourceRoot -B $buildRoot -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_C_COMPILER="$($clang.Source)" `
    -DCMAKE_CXX_COMPILER="$($clang.Source)" `
    -DOLDABI_COMPAT=OFF

Write-Step 'Building libobjc2'
& cmake --build $buildRoot

Write-Host "`nlibobjc2 source: $sourceRoot"
Write-Host "libobjc2 build:  $buildRoot"
