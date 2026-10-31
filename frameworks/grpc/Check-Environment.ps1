<#
.SYNOPSIS
    Tell a developer -- on THEIR machine -- which prebuilt gRPC package to use and how
    to build against it. Read-only, no admin, no network.

.DESCRIPTION
    Fleets are not uniform: different Visual Studio versions, different CMake versions.
    The prebuilt static libraries are ABI-locked to an MSVC toolset, so this script
    detects the installed MSVC toolset(s) and CMake, then prints:
      * which grpc-1.83.0-msvc<NNN>-release package matches,
      * whether CMakePresets.json can be used (needs CMake >= 3.21), and
      * the exact configure command to copy/paste.

.EXAMPLE
    .\Check-Environment.ps1
#>
[CmdletBinding()]
param()

function Get-ToolsetName([string]$v) {
    # MSVC tools version (e.g. 14.44.35207) -> platform toolset
    if ($v -match '^(\d+)\.(\d+)') {
        $minor = [int]$Matches[2]
        switch ($minor) {
            { $_ -ge 10 -and $_ -le 16 } { return 'v141' }  # VS 2017
            { $_ -ge 20 -and $_ -le 29 } { return 'v142' }  # VS 2019
            { $_ -ge 30 -and $_ -le 49 } { return 'v143' }  # VS 2022
            { $_ -ge 50 }                { return 'v145' }  # VS 2026
        }
    }
    return $null
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " gRPC 1.83.0 prebuilt -- environment check" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# --- Detect installed MSVC toolsets ------------------------------------------
function Get-GeneratorForProduct([string]$productDir) {
    # Map a VS product folder name to its CMake generator.
    switch -Regex ($productDir) {
        '(^|\D)18($|\D)|2026' { 'Visual Studio 18 2026'; break }
        '2022'                { 'Visual Studio 17 2022'; break }
        '2019'                { 'Visual Studio 16 2019'; break }
        '2017'                { 'Visual Studio 15 2017'; break }
        default               { 'Visual Studio 18 2026' }
    }
}

$roots = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio','C:\Program Files (x86)\Microsoft Visual Studio' `
    -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue }
# Track, per toolset: the MSVC version and the generator of the VS product that hosts it.
$toolsets = @{}
foreach ($r in $roots) {
    $tp = Join-Path $r.FullName 'VC\Tools\MSVC'
    if (-not (Test-Path $tp)) { continue }
    $gen = Get-GeneratorForProduct $r.Name
    foreach ($m in (Get-ChildItem $tp -Directory -ErrorAction SilentlyContinue)) {
        $ts = Get-ToolsetName $m.Name
        if ($ts) { $toolsets[$ts] = @{ Version = $m.Name; Generator = $gen } }
    }
}

Write-Host "`nInstalled MSVC toolsets:" -ForegroundColor Yellow
if ($toolsets.Count -eq 0) {
    Write-Host "  (none found -- install the 'Desktop development with C++' workload)" -ForegroundColor Red
} else {
    foreach ($k in $toolsets.Keys) { "  {0}  (MSVC {1}, {2})" -f $k, $toolsets[$k].Version, $toolsets[$k].Generator }
}

# --- Detect CMake -------------------------------------------------------------
$cmakeVer = $null
$cm = Get-Command cmake -ErrorAction SilentlyContinue
if ($cm) {
    $line = (& cmake --version | Select-Object -First 1)
    if ($line -match '(\d+\.\d+\.\d+)') { $cmakeVer = [version]$Matches[1] }
}
Write-Host "`nCMake:" -ForegroundColor Yellow
if ($cmakeVer) { "  $cmakeVer" + $(if ($cmakeVer -ge [version]'3.21') { '  (supports CMakePresets)' } else { '  (too old for presets -- use the manual configure below)' }) }
else { "  (cmake not on PATH)" }

# --- Recommendation -----------------------------------------------------------
Write-Host "`nRecommendation:" -ForegroundColor Yellow
$supported = $toolsets.Keys | Where-Object { $_ -in 'v143','v145' }
if (-not $supported) {
    Write-Host "  No prebuilt package matches your compiler." -ForegroundColor Red
    Write-Host "  Available packages are v143 (VS 2022) and v145 (VS 2026)."
    if ($toolsets.ContainsKey('v141') -or $toolsets.ContainsKey('v142')) {
        Write-Host "  You have v141/v142 (VS 2017/2019). A maintainer must build a matching"
        Write-Host "  package (scripts\build-grpc.ps1 -Toolset v141|v142) with that toolset staged."
    }
    return
}
foreach ($ts in $supported) {
    $pkg = "grpc-1.83.0-msvc$($ts.Substring(1))-release"
    $gen = $toolsets[$ts].Generator
    # Only VS 2026's generator needs an explicit -T toolset selection (it hosts multiple).
    $tflag = if ($gen -eq 'Visual Studio 18 2026') { " -T $ts,version=$($toolsets[$ts].Version)" } else { '' }
    Write-Host "  Use package: $pkg" -ForegroundColor Green
    Write-Host "  Configure your project with:"
    if ($cmakeVer -and $cmakeVer -ge [version]'3.21') {
        Write-Host "    cmake --preset vs2026-$ts        (or open the folder in VS Code / Visual Studio)"
    }
    Write-Host "    cmake -G `"$gen`" -A x64$tflag ``"
    Write-Host "          -DCMAKE_TOOLCHAIN_FILE=`"%GRPC_ROOT%\grpc-toolchain.cmake`" ``"
    Write-Host "          -DCMAKE_PREFIX_PATH=`"%GRPC_ROOT%`" -B build"
    Write-Host ""
}
Write-Host "First run activate.ps1 from the extracted package to set GRPC_ROOT." -ForegroundColor Cyan
