<#
.SYNOPSIS
    Start Dart Sass in --watch mode for all non-partial .scss files under a path.
    Replaces the VS Code Live Sass Compiler "Watch Sass" feature.

.PARAMETER Path
    Directory to scan. Defaults to current directory.

.PARAMETER Exclude
    Additional exclusion patterns (combined with .scss-compile.json defaults).

.PARAMETER ExpandedOnly
    Watch only expanded .css output (skip .min.css). Faster, less console noise.

.NOTES
    Runs two sass --watch processes (expanded + compressed) in parallel unless
    -ExpandedOnly is used. Ctrl+C to stop. Output from both processes is
    interleaved in the current console.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = (Get-Location).Path,

    [string[]]$Exclude = @(),

    [switch]$ExpandedOnly
)

$ErrorActionPreference = 'Stop'

$DefaultExcludes = @('node_modules', '.git', 'vendor', 'dist', 'build')

function Resolve-SassBin {
    $cmd = Get-Command sass -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:APPDATA 'npm\sass.cmd'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Get-RelPath([string]$baseDir, [string]$target) {
    $baseFull   = [IO.Path]::GetFullPath($baseDir.TrimEnd('\','/') + '\')
    $targetFull = [IO.Path]::GetFullPath($target)
    $baseUri    = New-Object System.Uri($baseFull)
    $targetUri  = New-Object System.Uri($targetFull)
    $rel        = $baseUri.MakeRelativeUri($targetUri).ToString()
    $rel        = [System.Uri]::UnescapeDataString($rel)
    return $rel -replace '/', '\'
}

function Read-ConfigExcludes([string]$baseDir) {
    $cfgPath = Join-Path $baseDir '.scss-compile.json'
    if (-not (Test-Path $cfgPath)) { return @() }
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($cfg.exclude) { return @($cfg.exclude) }
    } catch {
        Write-Host "[WARN] Could not parse .scss-compile.json" -ForegroundColor Yellow
    }
    return @()
}

function Test-Excluded([string]$relPath, [string[]]$patterns) {
    $n = ($relPath -replace '\\', '/').Trim('/')
    foreach ($p in $patterns) {
        if (-not $p) { continue }
        $pn = ($p -replace '\\', '/').Trim('/').Trim('*').TrimEnd('/')
        if (-not $pn) { continue }
        if ($n -eq $pn) { return $true }
        if ($n.StartsWith($pn + '/')) { return $true }
        if (("/" + $n + "/") -match ("/" + [regex]::Escape($pn) + "/")) { return $true }
    }
    return $false
}

try {
    $sassBin = Resolve-SassBin
    if (-not $sassBin) {
        Write-Error "sass CLI not found. Install with: npm install -g sass"
        exit 2
    }
    if (-not (Test-Path $Path)) {
        Write-Error "Path not found: $Path"
        exit 2
    }

    $resolved = (Resolve-Path $Path).Path
    $configExcludes = Read-ConfigExcludes $resolved
    $effectiveExcludes = @(@($DefaultExcludes) + @($configExcludes) + @($Exclude) | Where-Object { $_ } | Select-Object -Unique)

    Push-Location $resolved
    try {
        $all = Get-ChildItem -Recurse -Filter '*.scss' -File -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.StartsWith('_') }

        $files = @()
        foreach ($f in $all) {
            $rel = Get-RelPath $resolved $f.FullName
            if (-not (Test-Excluded $rel $effectiveExcludes)) { $files += $f }
        }

        if (-not $files -or $files.Count -eq 0) {
            Write-Host "No non-partial .scss files found under $resolved"
            exit 0
        }

        $pairsExpanded = @()
        $pairsMin      = @()
        foreach ($f in $files) {
            $relIn  = Get-RelPath $resolved $f.FullName
            $outDir = Split-Path -Parent $f.DirectoryName
            $base   = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            $relOutCss = Get-RelPath $resolved (Join-Path $outDir "$base.css")
            $relOutMin = Get-RelPath $resolved (Join-Path $outDir "$base.min.css")
            $pairsExpanded += "${relIn}:${relOutCss}"
            $pairsMin      += "${relIn}:${relOutMin}"
        }

        Write-Host "Watching $($files.Count) file(s) under $resolved" -ForegroundColor Cyan
        foreach ($f in $files) {
            Write-Host "  - $(Get-RelPath $resolved $f.FullName)" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
        Write-Host ""

        $procs = @()
        $argsExpanded = @('--watch', '--style=expanded', '--source-map') + $pairsExpanded
        $p1 = Start-Process -FilePath $sassBin -ArgumentList $argsExpanded -NoNewWindow -PassThru
        $procs += $p1

        if (-not $ExpandedOnly) {
            $argsMin = @('--watch', '--style=compressed', '--source-map') + $pairsMin
            $p2 = Start-Process -FilePath $sassBin -ArgumentList $argsMin -NoNewWindow -PassThru
            $procs += $p2
        }

        try {
            Wait-Process -Id ($procs.Id) -ErrorAction SilentlyContinue
        }
        finally {
            foreach ($p in $procs) {
                if ($p -and -not $p.HasExited) {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host ""
            Write-Host "Stopped watching." -ForegroundColor Yellow
        }
        exit 0
    }
    finally {
        Pop-Location
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
