Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-PathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Entry
    )

    if (-not (Test-Path $Entry)) {
        return
    }

    $existing = @($env:Path -split ';' | Where-Object { $_ })
    if ($existing -contains $Entry) {
        return
    }

    $env:Path = "$Entry;$env:Path"
}

function Import-BatchEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchFile,

        [string[]]$Arguments = @()
    )

    if (-not (Test-Path $BatchFile)) {
        return
    }

    $argumentText = ($Arguments | ForEach-Object { $_.Trim() }) -join ' '
    $commandText = if ($argumentText) {
        "`"$BatchFile`" $argumentText && set"
    } else {
        "`"$BatchFile`" && set"
    }

    cmd.exe /s /c $commandText | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
        }
    }
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

function Find-ExecutableUnderRoots {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots
    )

    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
            continue
        }

        $match = Get-ChildItem $root -Filter $Name -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($match) {
            return $match
        }
    }

    return $null
}

function Find-DirectoryUnderRoots {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots
    )

    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
            continue
        }

        $match = Get-ChildItem $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $Name } |
            Select-Object -First 1 -ExpandProperty FullName
        if ($match) {
            return $match
        }
    }

    return $null
}

$hostArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
    $env:PROCESSOR_ARCHITEW6432
} else {
    $env:PROCESSOR_ARCHITECTURE
}
$normalizedHostArchitecture = switch ($hostArchitecture.ToUpperInvariant()) {
    'ARM64' { 'arm64' }
    default { 'x64' }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$env:IPHONE_EMULATOR_WINDOWS_ROOT = $repoRoot
$env:IPHONE_EMULATOR_HOST_ARCH = $normalizedHostArchitecture
$env:IPHONE_EMULATOR_LIBOBJC2_SRC = Join-Path $repoRoot 'vendor\libobjc2-src'
$env:IPHONE_EMULATOR_LIBOBJC2_BUILD = Join-Path $repoRoot "vendor\libobjc2-build-$normalizedHostArchitecture"

$vsInstallPath = Get-VisualStudioInstallPath
if ($vsInstallPath) {
    $vsDevCmd = Join-Path $vsInstallPath 'Common7\Tools\VsDevCmd.bat'
    $launchDevCmd = Join-Path $vsInstallPath 'Common7\Tools\LaunchDevCmd.bat'
    if (Test-Path $vsDevCmd) {
        Import-BatchEnvironment -BatchFile $vsDevCmd -Arguments @('-no_logo', "-arch=$normalizedHostArchitecture")
    } elseif (Test-Path $launchDevCmd) {
        Import-BatchEnvironment -BatchFile $launchDevCmd -Arguments @('-no_logo', "-arch=$normalizedHostArchitecture")
    }
}

$swiftPath = Find-ExecutableUnderRoots -Name 'swift.exe' -Roots @(
    'C:\Library\Developer\Toolchains',
    (Join-Path $env:LOCALAPPDATA 'Programs\Swift')
)
if ($swiftPath) {
    Add-PathEntry (Split-Path -Parent $swiftPath)

    $toolchainRoot = Split-Path (Split-Path (Split-Path $swiftPath -Parent) -Parent) -Parent
    $swiftProgramsRoot = Split-Path (Split-Path $toolchainRoot -Parent) -Parent
    $toolchainVersion = ($toolchainRoot | Split-Path -Leaf) -replace '\+.*$', ''
    $sdkRoot = Join-Path $swiftProgramsRoot "Platforms\$toolchainVersion\Windows.platform\Developer\SDKs\Windows.sdk"
    if (Test-Path $sdkRoot) {
        $env:SDKROOT = $sdkRoot
    }
    $runtimeBin = Join-Path $swiftProgramsRoot "Runtimes\$toolchainVersion\usr\bin"
    if (-not (Test-Path $runtimeBin)) {
        $runtimeBin = Find-DirectoryUnderRoots -Name 'bin' -Roots @(
            (Join-Path $swiftProgramsRoot 'Runtimes')
        )
    }
    if ($runtimeBin) {
        Add-PathEntry $runtimeBin
    }

    Add-PathEntry (Join-Path $toolchainRoot 'usr\lib\swift\pm\ManifestAPI')
    Add-PathEntry (Join-Path $toolchainRoot 'usr\lib\swift\pm\PluginAPI')
}

$visualStudioRedistRoot = Join-Path $vsInstallPath 'VC\Redist\MSVC'
if (Test-Path $visualStudioRedistRoot) {
    $vcRuntimeDir = Get-ChildItem $visualStudioRedistRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
            $candidate = Join-Path $_.FullName "$normalizedHostArchitecture\Microsoft.VC145.CRT"
            if (Test-Path $candidate) {
                $candidate
                break
            }
        } |
        Select-Object -First 1
    if ($vcRuntimeDir) {
        Add-PathEntry $vcRuntimeDir
    }
}

Add-PathEntry 'C:\Program Files\CMake\bin'
Add-PathEntry 'C:\Program Files\LLVM\bin'
Add-PathEntry (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python310')
Add-PathEntry 'C:\msys64\usr\bin'
Add-PathEntry 'C:\msys64\mingw64\bin'

$nasmPath = Find-ExecutableUnderRoots -Name 'nasm.exe' -Roots @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
    $env:ProgramFiles,
    (Join-Path $env:LOCALAPPDATA 'Programs')
)
if ($nasmPath) {
    Add-PathEntry (Split-Path -Parent $nasmPath)
}

Write-Host "Windows toolchain environment loaded for $repoRoot ($normalizedHostArchitecture)"
foreach ($tool in 'swift','cl','msbuild','cmake','clang','nasm') {
    $resolved = Get-Command $tool -ErrorAction SilentlyContinue
    if ($resolved) {
        Write-Host " - $tool => $($resolved.Source)"
    } else {
        Write-Host " - $tool => MISSING"
    }
}
