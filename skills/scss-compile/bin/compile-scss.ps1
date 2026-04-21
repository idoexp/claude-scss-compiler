<#
.SYNOPSIS
    Recompile all non-partial .scss files under a path, matching VS Code
    Live Sass Compiler behavior (expanded + compressed, source maps,
    output to parent folder of the .scss file's directory).

.PARAMETER Path
    Directory to scan recursively. Defaults to the current working directory.

.PARAMETER Exclude
    One or more path patterns to exclude. Matches against directory segments
    or prefix paths. Combined with `exclude` from .scss-compile.json (if present).

.EXAMPLE
    compile-scss.ps1
    compile-scss.ps1 -Path .\src\assets\css
    compile-scss.ps1 -Exclude legacy,old

.NOTES
    Reads .scss-compile.json at the target path root if present.
    Format: { "exclude": ["folder_a", "path/to/folder_b"] }
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = (Get-Location).Path,

    [string[]]$Exclude = @()
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
        Write-Host "[WARN] Could not parse .scss-compile.json ($($_.Exception.Message))" -ForegroundColor Yellow
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

    if ($configExcludes.Count -gt 0) {
        Write-Host "Loaded $($configExcludes.Count) exclusion(s) from .scss-compile.json" -ForegroundColor Gray
    }

    Push-Location $resolved
    try {
        $all = Get-ChildItem -Recurse -Filter '*.scss' -File -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.StartsWith('_') }

        $files = @()
        $skipped = 0
        foreach ($f in $all) {
            $rel = Get-RelPath $resolved $f.FullName
            if (Test-Excluded $rel $effectiveExcludes) {
                $skipped++
            } else {
                $files += $f
            }
        }

        if (-not $files -or $files.Count -eq 0) {
            Write-Host "No non-partial .scss files found under $resolved (skipped $skipped excluded)"
            exit 0
        }

        $pairsExpanded = [System.Collections.Generic.List[string]]::new()
        $pairsMin      = [System.Collections.Generic.List[string]]::new()

        foreach ($f in $files) {
            $relIn  = Get-RelPath $resolved $f.FullName
            $outDir = Split-Path -Parent $f.DirectoryName
            $base   = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            $relOutCss = Get-RelPath $resolved (Join-Path $outDir "$base.css")
            $relOutMin = Get-RelPath $resolved (Join-Path $outDir "$base.min.css")
            $pairsExpanded.Add("${relIn}:${relOutCss}")
            $pairsMin.Add("${relIn}:${relOutMin}")
        }

        $summary = "Compiling $($files.Count) file(s) from $resolved"
        if ($skipped -gt 0) { $summary += " (skipped $skipped by exclusion)" }
        Write-Host "$summary..."
        foreach ($f in $files) {
            $rel = Get-RelPath $resolved $f.FullName
            Write-Host "  - $rel"
        }

        Write-Host ""
        Write-Host "-> Expanded (.css)..."
        & $sassBin --style=expanded --source-map @pairsExpanded
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "[ERROR] sass failed while generating expanded output (see errors above)." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        Write-Host "-> Compressed (.min.css)..."
        & $sassBin --style=compressed --source-map @pairsMin
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "[ERROR] sass failed while generating compressed output (see errors above)." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        Write-Host ""
        Write-Host "OK: $($files.Count) file(s) compiled (expanded + min)." -ForegroundColor Green
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
