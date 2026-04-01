Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message"
}

function Test-DeveloperModeEnabled {
    $item = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue
    if (-not $item) {
        return $false
    }

    $property = $item.PSObject.Properties['AllowDevelopmentWithoutDevLicense']
    if (-not $property) {
        return $false
    }

    $value = $property.Value
    return $value -eq 1
}

function Ensure-WingetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [string]$InstallArgs = ''
    )

    $installed = winget list --id $Id --exact --accept-source-agreements 2>$null | Select-String -SimpleMatch $Id
    if ($installed) {
        Write-Host "Already installed: $Id"
        return
    }

    $command = @(
        'install',
        '--id', $Id,
        '--exact',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    if ($InstallArgs) {
        $command += @('--override', $InstallArgs)
    }

    Write-Host "Installing: $Id"
    & winget @command
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

function Resolve-NewestMSVCPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Suffix
    )

    $msvcRoot = Join-Path $InstallPath 'VC\Tools\MSVC'
    if (-not (Test-Path $msvcRoot)) {
        return $null
    }

    $versions = Get-ChildItem $msvcRoot -Directory | Sort-Object Name -Descending
    foreach ($version in $versions) {
        $candidate = $version.FullName
        foreach ($part in $Suffix) {
            $candidate = Join-Path $candidate $part
        }

        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-Windows11SDKPath {
    param(
        [int]$MinimumBuild = 22000
    )

    $sdkRoot = 'C:\Program Files (x86)\Windows Kits\10\Include'
    if (-not (Test-Path $sdkRoot)) {
        return $null
    }

    $candidates = Get-ChildItem $sdkRoot -Directory |
        Where-Object { $_.Name -match '^10\.0\.(\d+)\.\d+$' } |
        ForEach-Object {
            $build = [int]([regex]::Match($_.Name, '^10\.0\.(\d+)\.\d+$').Groups[1].Value)
            [PSCustomObject]@{
                Build = $build
                Path = $_.FullName
            }
        } |
        Where-Object { $_.Build -ge $MinimumBuild } |
        Sort-Object Build -Descending, Path -Descending

    return ($candidates | Select-Object -First 1).Path
}

function Get-NormalizedHostArchitecture {
    $hostArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    } else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch ($hostArchitecture.ToUpperInvariant()) {
        'ARM64' { 'arm64' }
        default { 'x64' }
    }
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $resolved = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw "Required command '$Name' is not available in this session. Dot-source .\scripts\env-windows.ps1 and retry."
    }

    Write-Host "Validated $Name => $($resolved.Source)"
}

Write-Step 'Checking Developer Mode'
if (-not (Test-DeveloperModeEnabled)) {
    throw 'Developer Mode is disabled. Enable it in Settings > For developers before running the native Windows bootstrap.'
}
Write-Host 'Developer Mode is enabled.'

$hostArchitecture = Get-NormalizedHostArchitecture
Write-Host "Detected host architecture: $hostArchitecture"

Write-Step 'Installing or validating core packages'
Ensure-WingetPackage -Id 'Swift.Toolchain'
Ensure-WingetPackage -Id 'Python.Python.3.10'
Ensure-WingetPackage -Id 'LLVM.LLVM'
Ensure-WingetPackage -Id 'Kitware.CMake'
Ensure-WingetPackage -Id 'MSYS2.MSYS2'
Ensure-WingetPackage -Id 'NASM.NASM'

$visualStudioInstallPath = Get-VisualStudioInstallPath
$x64Compiler = if ($visualStudioInstallPath) { Resolve-NewestMSVCPath -InstallPath $visualStudioInstallPath -Suffix @('bin', 'Hostx64', 'x64', 'cl.exe') } else { $null }
$arm64Compiler = if ($visualStudioInstallPath) { Resolve-NewestMSVCPath -InstallPath $visualStudioInstallPath -Suffix @('bin', 'Hostx64', 'arm64', 'cl.exe') } else { $null }
$windows11Sdk = Resolve-Windows11SDKPath -MinimumBuild 22000

if (-not $visualStudioInstallPath -or -not $x64Compiler -or -not $arm64Compiler -or -not $windows11Sdk) {
    Write-Step 'Installing or updating Visual Studio Build Tools components'
    Ensure-WingetPackage -Id 'Microsoft.VisualStudio.2022.BuildTools' -InstallArgs '--wait --quiet --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64'
}

Write-Step 'Loading the Windows toolchain environment'
. (Join-Path $PSScriptRoot 'env-windows.ps1')

Write-Step 'Validating native commands'
foreach ($tool in 'swift','cl','msbuild','cmake','clang','nasm') {
    Assert-CommandAvailable -Name $tool
}

Write-Step 'Swift toolchain version'
& swift --version

Write-Host "`nNext step:"
Write-Host '  . .\scripts\env-windows.ps1'
