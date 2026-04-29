param(
    [string]$Repo = $env:ZROUTER_INSTALL_REPO,
    [string]$Version = $env:ZROUTER_VERSION,
    [string]$InstallDir = $env:ZROUTER_INSTALL_DIR,
    [string]$CurrentVersion = $env:ZROUTER_CURRENT_VERSION,
    [string]$InstallSkill = $env:ZROUTER_INSTALL_SKILL,
    [string]$SkillSpec = $env:ZROUTER_SKILL_SPEC
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = "Teamon9161/zrouter"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "latest"
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\zrouter\bin"
}

if ([string]::IsNullOrWhiteSpace($InstallSkill)) {
    $InstallSkill = "auto"
}

if ([string]::IsNullOrWhiteSpace($SkillSpec)) {
    $SkillSpec = "@Teamon9161/zrouter/skill"
}

function Write-SkillGuidance {
    Write-Host ""
    Write-Host "zrouter skill path:"
    Write-Host "  $SkillSpec"
    Write-Host "Install it later with:"
    Write-Host "  skill -A $SkillSpec"
}

function Install-ZrouterSkill {
    $SkillCommand = Get-Command skill -ErrorAction SilentlyContinue
    if (-not $SkillCommand) {
        Write-Host "skill CLI not found; skipping zrouter skill installation."
        Write-SkillGuidance
        return $false
    }

    & skill -A $SkillSpec
    if ($LASTEXITCODE -ne 0) {
        throw "skill installation failed"
    }
    return $true
}

function Maybe-InstallSkill {
    switch -Regex ($InstallSkill) {
        "^(0|false|no|skip)$" {
            Write-SkillGuidance
            return
        }
        "^(1|true|yes)$" {
            if (-not (Install-ZrouterSkill)) { exit 1 }
            return
        }
    }

    if (-not (Get-Command skill -ErrorAction SilentlyContinue)) {
        Write-SkillGuidance
        return
    }

    if ([Environment]::UserInteractive) {
        $Answer = Read-Host "Install the zrouter skill now? [Y/n]"
        if ($Answer -match "^(n|N|no|NO|No)$") {
            Write-SkillGuidance
        } else {
            try {
                Install-ZrouterSkill | Out-Null
            } catch {
                Write-Host $_.Exception.Message
                Write-SkillGuidance
            }
        }
    } else {
        Write-SkillGuidance
    }
}

if ($Version -eq "latest" -and -not [string]::IsNullOrWhiteSpace($CurrentVersion)) {
    try {
        $ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
        $Release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "zrouter-updater" }
        $LatestVersion = $Release.tag_name.TrimStart("v")
        if ([Version]$CurrentVersion -ge [Version]$LatestVersion) {
            Write-Host "zrouter $CurrentVersion is already up to date"
            exit 0
        }
        Write-Host "Updating zrouter $CurrentVersion -> $LatestVersion..."
    } catch {
        Write-Host "Warning: could not check latest version, proceeding with update..."
    }
}

$processor = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
switch -Regex ($processor) {
    "ARM64" { $Arch = "aarch64"; break }
    "AMD64|x86_64" { $Arch = "x86_64"; break }
    default {
        throw "unsupported architecture: $processor"
    }
}

$Archive = "zrouter-$Arch-windows.zip"
if ($Version -eq "latest") {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
} else {
    if ($Version.StartsWith("v")) {
        $Tag = $Version
    } else {
        $Tag = "v$Version"
    }
    $BaseUrl = "https://github.com/$Repo/releases/download/$Tag"
}

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("zrouter-install-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TempDir | Out-Null

try {
    $ArchivePath = Join-Path $TempDir $Archive
    $ChecksumsPath = Join-Path $TempDir "checksums.txt"

    Write-Host "Downloading $Archive..."
    Invoke-WebRequest -Uri "$BaseUrl/$Archive" -OutFile $ArchivePath
    Write-Host "Downloading checksums..."
    Invoke-WebRequest -Uri "$BaseUrl/checksums.txt" -OutFile $ChecksumsPath

    $ChecksumLine = Get-Content $ChecksumsPath | Where-Object {
        ($_ -split "\s+")[-1] -eq $Archive
    } | Select-Object -First 1

    if (-not $ChecksumLine) {
        throw "checksum not found for $Archive"
    }

    $Expected = ($ChecksumLine -split "\s+")[0].ToLowerInvariant()
    $Actual = (Get-FileHash -Algorithm SHA256 $ArchivePath).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) {
        throw "checksum mismatch for $Archive"
    }

    Expand-Archive -Path $ArchivePath -DestinationPath $TempDir -Force
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    $BinaryPath = Join-Path $TempDir "zrouter.exe"
    if (-not (Test-Path $BinaryPath)) {
        throw "archive did not contain zrouter.exe"
    }

    $Target = Join-Path $InstallDir "zrouter.exe"
    $OldExe = Join-Path $InstallDir "zrouter.exe.old"
    if (Test-Path $OldExe) { Remove-Item $OldExe -Force -ErrorAction SilentlyContinue }
    if (Test-Path $Target) { Rename-Item -Path $Target -NewName "zrouter.exe.old" -Force }
    Copy-Item -Path $BinaryPath -Destination $Target -Force
    Remove-Item $OldExe -Force -ErrorAction SilentlyContinue

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PathParts = @()
    if (-not [string]::IsNullOrWhiteSpace($UserPath)) {
        $PathParts = $UserPath -split ";"
    }

    if ($PathParts -notcontains $InstallDir) {
        $NewUserPath = if ([string]::IsNullOrWhiteSpace($UserPath)) {
            $InstallDir
        } else {
            "$UserPath;$InstallDir"
        }
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    }

    if (($env:Path -split ";") -notcontains $InstallDir) {
        $env:Path = "$env:Path;$InstallDir"
    }

    Write-Host "zrouter installed to $(Join-Path $InstallDir "zrouter.exe")"
    Write-Host "Restart your terminal if zrouter is not found in PATH."
    Maybe-InstallSkill
} finally {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
