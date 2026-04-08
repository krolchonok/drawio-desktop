param(
    [string]$Target,
    [string]$Version,
    [switch]$KeepUpdates
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

$NpmExe = (Get-Command "npm.cmd" -ErrorAction SilentlyContinue).Source
if (-not $NpmExe) { $NpmExe = "npm" }

$NpxExe = (Get-Command "npx.cmd" -ErrorAction SilentlyContinue).Source
if (-not $NpxExe) { $NpxExe = "npx" }

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Allowed
    )

    while ($true) {
        $value = Read-Host $Prompt
        if ($Allowed -contains $value) {
            return $value
        }
        Write-Host "Invalid option. Allowed: $($Allowed -join ', ')"
    }
}

function Read-YesNo {
    param([string]$Prompt)

    while ($true) {
        $value = (Read-Host "$Prompt [y/n]").ToLowerInvariant()
        if ($value -in @("y", "yes")) { return $true }
        if ($value -in @("n", "no")) { return $false }
        Write-Host "Please enter y or n."
    }
}

if (-not (Test-Path "package.json")) {
    throw "Run this script from the drawio-desktop repo root."
}

$drawioVersionPath = Join-Path "drawio" "VERSION"
if (-not (Test-Path $drawioVersionPath)) {
    $hasDrawioSubmodule = $false
    if (Test-Path ".gitmodules") {
        $hasDrawioSubmodule = (Select-String -Path ".gitmodules" -Pattern 'path\s*=\s*drawio' -Quiet)
    }

    if ($hasDrawioSubmodule) {
        throw "drawio\VERSION not found. The drawio submodule looks uninitialized. Run: git submodule update --init --recursive"
    }

    throw "drawio\VERSION not found at '$drawioVersionPath'."
}

$targets = [ordered]@{
    "1" = @{
        Key = "portable-x64"
        Description = "Portable EXE x64"
        Args = @("electron-builder", "--config", "electron-builder-win.json", "--win", "portable", "--x64", "--publish", "never")
    }
    "2" = @{
        Key = "installer-x64-admin"
        Description = "Installer NSIS x64 (admin/per-machine)"
        Args = @("electron-builder", "--config", "electron-builder-win.json", "--win", "nsis", "--x64", "--publish", "never", "--config.nsis.perMachine=true", "--config.nsis.allowElevation=true")
    }
    "3" = @{
        Key = "installer-x64-user"
        Description = "Installer NSIS x64 (no admin/per-user)"
        Args = @("electron-builder", "--config", "electron-builder-win.json", "--win", "nsis", "--x64", "--publish", "never", "--config.nsis.perMachine=false", "--config.nsis.allowElevation=false")
    }
    "4" = @{
        Key = "installer-win32"
        Description = "Installer NSIS ia32 (32-bit)"
        Args = @("electron-builder", "--config", "electron-builder-win32.json", "--publish", "never")
    }
    "5" = @{
        Key = "installer-arm64"
        Description = "Installer + portable ARM64"
        Args = @("electron-builder", "--config", "electron-builder-win-arm64.json", "--publish", "never")
    }
    "6" = @{
        Key = "appx"
        Description = "APPX package"
        Args = @("electron-builder", "--config", "electron-builder-appx.json", "--publish", "never")
    }
}

if (-not $Target) {
    Write-Host "Select build target:"
    foreach ($id in $targets.Keys) {
        $item = $targets[$id]
        Write-Host "  $id) $($item.Description) [$($item.Key)]"
    }
    $selected = Read-Choice -Prompt "Enter number" -Allowed $targets.Keys
    $Target = $targets[$selected].Key
}

$selectedTarget = $null
foreach ($id in $targets.Keys) {
    if ($targets[$id].Key -eq $Target) {
        $selectedTarget = $targets[$id]
        break
    }
}

if (-not $selectedTarget) {
    throw "Unknown target '$Target'. Valid keys: $((($targets.Values | ForEach-Object { $_.Key }) -join ', '))"
}

$currentVersion = (Get-Content $drawioVersionPath -Raw).Trim()
if (-not $Version) {
    Write-Host "Current drawio version: $currentVersion"
    if (Read-YesNo "Change version?") {
        $Version = Read-Host "Enter new version (example: 29.3.8)"
    }
}

if ($Version) {
    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw "Version cannot be empty."
    }

    Set-Content $drawioVersionPath $Version -NoNewline
    Write-Host "Version updated: $Version"
}

if (-not (Test-Path "node_modules")) {
    Write-Host "node_modules not found. Running npm install..."
    & $NpmExe install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed with code $LASTEXITCODE" }
}

$disableUpdate = -not $KeepUpdates
if ($disableUpdate) {
    Write-Host "Syncing package version (updates disabled)..."
    & $NpmExe run sync -- disableUpdate
}
else {
    Write-Host "Syncing package version..."
    & $NpmExe run sync
}
if ($LASTEXITCODE -ne 0) { throw "npm run sync failed with code $LASTEXITCODE" }

Write-Host "Building: $($selectedTarget.Description)"
Write-Host "Command: npx $($selectedTarget.Args -join ' ')"
& $NpxExe @($selectedTarget.Args)
if ($LASTEXITCODE -ne 0) { throw "Build failed with code $LASTEXITCODE" }

Write-Host ""
Write-Host "Build completed. Latest artifacts in build\:"
Get-ChildItem "build" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 Name, Length, LastWriteTime |
    Format-Table -AutoSize
