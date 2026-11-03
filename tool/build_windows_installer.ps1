# Builds the Windows installer (Inno Setup) from an existing `flutter build windows --release`
# output, then installs and uninstalls it silently as a smoke test.
#
#   pwsh tool/build_windows_installer.ps1 -Arch x64 -Version 1.0.0 -OutputName tokenbar-v1.0.0-windows-x64-setup
#
# Used by .github/workflows/ci.yml and release.yml. ASCII only on purpose.
param(
  [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
  [Parameter(Mandatory)][string]$Version,
  [Parameter(Mandatory)][string]$OutputName,
  [string]$OutputDir = 'dist'
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

# --- PE helpers ---------------------------------------------------------------------------
function Get-PeMachine([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $pe = [BitConverter]::ToInt32($bytes, 0x3C)
  return '{0:X4}' -f [BitConverter]::ToUInt16($bytes, $pe + 4)
}
$expected = if ($Arch -eq 'arm64') { 'AA64' } else { '8664' }

# --- Stage the app ------------------------------------------------------------------------
$release = Join-Path $root "build/windows/$Arch/runner/Release"
$exe = Join-Path $release 'token_bar.exe'
if (-not (Test-Path $exe)) { throw "token_bar.exe not found in $release (run flutter build windows first)" }
$machine = Get-PeMachine $exe
if ($machine -ne $expected) { throw "token_bar.exe is 0x$machine, expected 0x$expected for $Arch" }

$stage = Join-Path $root "build/installer-stage-$Arch"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse $release $stage

# App-local Visual C++ runtime, so the installed app starts on a clean machine.
# The files come from the build machine, which has the matching architecture.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $src = Join-Path $env:SystemRoot "System32/$dll"
  if (-not (Test-Path $src)) {
    Write-Warning "$dll not found in System32; it is not bundled."
    continue
  }
  $m = Get-PeMachine $src
  if ($m -ne $expected) {
    Write-Warning "$dll is 0x$m, expected 0x$expected; it is not bundled."
    continue
  }
  Copy-Item $src $stage -Force
  Write-Host "Bundled $dll"
}

# --- Inno Setup ---------------------------------------------------------------------------
function Find-Iscc {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  return $null
}
$iscc = Find-Iscc
if (-not $iscc) {
  Write-Host 'Installing Inno Setup with Chocolatey...'
  choco install innosetup -y --no-progress
  if ($LASTEXITCODE -ne 0) { throw 'choco install innosetup failed' }
  $iscc = Find-Iscc
}
if (-not $iscc) { throw 'ISCC.exe not found' }
Write-Host "Using $iscc"

$numeric = (($Version -split '-')[0]) + '.0'
$outDir = Join-Path $root $OutputDir
New-Item -ItemType Directory -Force $outDir | Out-Null

& $iscc "/Qp" "/DAppVersion=$Version" "/DNumericVersion=$numeric" "/DArch=$Arch" `
  "/DSourceDir=$stage" "/DOutputDir=$outDir" "/DOutputName=$OutputName" `
  (Join-Path $root 'windows/installer/tokenbar.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$setup = Join-Path $outDir "$OutputName.exe"
if (-not (Test-Path $setup)) { throw "$setup was not produced" }
Write-Host ("Installer: {0} ({1:N1} MB)" -f $setup, ((Get-Item $setup).Length / 1MB))

# --- Smoke test: silent per-user install, check the files, silent uninstall ---------------
$tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$target = Join-Path $tempBase "tokenbar-install-test-$Arch"
if (Test-Path $target) { Remove-Item -Recurse -Force $target }

$p = Start-Process -FilePath $setup -Wait -PassThru -ArgumentList @(
  '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', "/DIR=$target", '/NOICONS'
)
if ($p.ExitCode -ne 0) { throw "Installer exited with code $($p.ExitCode)" }
foreach ($f in 'token_bar.exe', 'flutter_windows.dll', 'data/app.so', 'unins000.exe') {
  if (-not (Test-Path (Join-Path $target $f))) { throw "Installed app is missing $f" }
}
Write-Host 'Install OK'

# The in-app updater installs over a running install with /relaunch=1 and expects the new version to
# start by itself. Do an upgrade-style run here and wait for the process (it is stopped right away).
$p = Start-Process -FilePath $setup -Wait -PassThru -ArgumentList @(
  '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', "/DIR=$target", '/NOICONS', '/relaunch=1'
)
if ($p.ExitCode -ne 0) { throw "Relaunch install exited with code $($p.ExitCode)" }
$started = $false
for ($i = 0; $i -lt 40 -and -not $started; $i++) {
  if (Get-Process -Name 'token_bar' -ErrorAction SilentlyContinue) { $started = $true } else { Start-Sleep -Milliseconds 250 }
}
Get-Process -Name 'token_bar' -ErrorAction SilentlyContinue | Stop-Process -Force
if (-not $started) { throw '/relaunch=1 did not start the installed app' }
Write-Host 'Relaunch OK'

$u = Start-Process -FilePath (Join-Path $target 'unins000.exe') -Wait -PassThru `
  -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
if ($u.ExitCode -ne 0) { throw "Uninstaller exited with code $($u.ExitCode)" }
# The uninstaller removes itself shortly after it exits.
for ($i = 0; $i -lt 20 -and (Test-Path (Join-Path $target 'token_bar.exe')); $i++) { Start-Sleep -Milliseconds 500 }
if (Test-Path (Join-Path $target 'token_bar.exe')) { throw 'Uninstall left token_bar.exe behind' }
Write-Host 'Uninstall OK'
