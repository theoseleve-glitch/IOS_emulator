Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Step 'Loading the native Windows toolchain environment'
. (Join-Path $PSScriptRoot 'env-windows.ps1')

Write-Step 'Verifying host architecture'
if ($env:IPHONE_EMULATOR_HOST_ARCH -ne 'arm64') {
    throw "validate-windows-arm64.ps1 must be run on a native Windows ARM64 host. Current host arch: $($env:IPHONE_EMULATOR_HOST_ARCH)"
}

$commands = @(
    'swift build',
    'swift test',
    'swift run EmulatorHost doctor --expected-arch arm64',
    'swift run EmulatorHost smoke',
    'swift run EmulatorHost ui-demo --autoclose-ms 1500',
    'swift run EmulatorHost bluetooth-check --backend mock',
    'swift run EmulatorHost app validate --package-path Examples/StarterTelemetryApp',
    'swift run EmulatorHost app run --package-path Examples/StarterTelemetryApp --renderer text',
    'swift run EmulatorHost app validate --package-path Examples/BluetoothTelemetryApp --bluetooth-backend mock',
    'swift run EmulatorHost app run --package-path Examples/BluetoothTelemetryApp --renderer text --bluetooth-backend mock',
    'swift run EmulatorHost app validate --package-path Examples/DeviceShowcaseApp',
    'swift run EmulatorHost app run --package-path Examples/DeviceShowcaseApp --renderer text',
    'swift run EmulatorHost app validate --package-path Examples/InputPlaygroundApp',
    'swift run EmulatorHost app run --package-path Examples/InputPlaygroundApp --renderer text'
)

foreach ($command in $commands) {
    Write-Step $command
    & powershell -NoProfile -Command $command
    if ($LASTEXITCODE -ne 0) {
        throw "ARM64 validation command failed: $command"
    }
}

Write-Host "`nARM64 validation OK"
