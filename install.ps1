<#
.SYNOPSIS
    One-click installer for the claude-scss-compiler skills bundle.

.DESCRIPTION
    Checks prerequisites (PowerShell, Claude Code, Node.js, npm, sass),
    installs anything missing via winget / npm, then deploys every skill
    under the bundled `skills/` folder to ~/.claude/skills/ and runs a
    self-test on the scss-compile skill.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Force   # overwrite existing skill without prompting
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$PackageName     = 'claude-scss-compiler'
$PackageVersion  = '1.1.0'
$MinNodeMajor    = 18
$MinSassMajorMin = @(1, 70)   # 1.70+
$MinClaudeVer    = [Version]'1.0.0'

$ScriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SourceSkillsDir = Join-Path $ScriptDir 'skills'
$TargetSkillsDir = Join-Path $HOME '.claude\skills'

function Write-Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Info([string]$msg) { Write-Host "    $msg" -ForegroundColor Gray }
function Write-Warn2([string]$msg){ Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "    [FAIL] $msg" -ForegroundColor Red }

function Exit-WithError([string]$msg, [string]$remediation = '') {
    Write-Host ""
    Write-Fail $msg
    if ($remediation) { Write-Host "    $remediation" -ForegroundColor Yellow }
    exit 1
}

function Get-CommandVersion([string]$cmd, [string]$arg = '--version') {
    $exe = Get-Command $cmd -ErrorAction SilentlyContinue
    if (-not $exe) { return $null }
    try {
        $out = & $exe.Source $arg 2>&1 | Out-String
        return $out.Trim()
    } catch { return $null }
}

function Refresh-EnvPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Extract-SemverMajor([string]$text) {
    if ($text -match '(\d+)\.(\d+)(?:\.(\d+))?') {
        return [int]$Matches[1]
    }
    return 0
}

function Extract-SemverTuple([string]$text) {
    if ($text -match '(\d+)\.(\d+)(?:\.(\d+))?') {
        return @([int]$Matches[1], [int]$Matches[2])
    }
    return @(0, 0)
}

try {
    Write-Host ""
    Write-Host "  $PackageName v$PackageVersion" -ForegroundColor White
    Write-Host "  Installs Claude Code skills (user-level)" -ForegroundColor Gray
    Write-Host "  Target: $TargetSkillsDir" -ForegroundColor Gray

    # 1. PowerShell version
    Write-Step "Checking PowerShell version"
    $psMajor = $PSVersionTable.PSVersion.Major
    if ($psMajor -lt 5) {
        Exit-WithError "PowerShell 5.1+ required (found $($PSVersionTable.PSVersion))." `
                      "Install Windows PowerShell 5.1 or PowerShell 7+ from https://aka.ms/powershell"
    }
    Write-Ok "PowerShell $($PSVersionTable.PSVersion)"

    # 2. Claude Code
    Write-Step "Checking Claude Code installation"
    $claudeHome = Join-Path $HOME '.claude'
    if (-not (Test-Path $claudeHome)) {
        Exit-WithError "Claude Code not detected (no $claudeHome folder)." `
                      "Install Claude Code: https://claude.com/claude-code"
    }
    $claudeVer = Get-CommandVersion 'claude'
    if ($claudeVer) {
        if ($claudeVer -match '(\d+\.\d+(?:\.\d+)?)') {
            $v = [Version]$Matches[1]
            if ($v -lt $MinClaudeVer) {
                Write-Warn2 "Claude Code $v found, recommended $MinClaudeVer+. Continuing anyway."
            } else {
                Write-Ok "Claude Code $v"
            }
        } else {
            Write-Ok "Claude Code ($claudeVer)"
        }
    } else {
        Write-Warn2 "`.claude/` present but `claude` CLI not in PATH. Skill deploy will still work."
    }

    # 3. Node.js
    Write-Step "Checking Node.js (>= $MinNodeMajor)"
    $nodeVer = Get-CommandVersion 'node'
    if (-not $nodeVer -or (Extract-SemverMajor $nodeVer) -lt $MinNodeMajor) {
        if ($nodeVer) { Write-Info "Found Node $nodeVer, need >= $MinNodeMajor. Upgrading via winget..." }
        else          { Write-Info "Node.js not found. Installing via winget..." }

        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Exit-WithError "winget not available (Windows 10 19H1+ or Windows 11 required)." `
                          "Install Node.js LTS manually from https://nodejs.org/ then rerun this installer."
        }

        & winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "winget install of Node.js failed (exit $LASTEXITCODE)." `
                          "Install Node.js LTS manually from https://nodejs.org/ then rerun this installer."
        }

        Refresh-EnvPath
        $nodeVer = Get-CommandVersion 'node'
        if (-not $nodeVer) {
            Exit-WithError "Node.js install completed but `node` is still not resolvable." `
                          "Close and reopen the terminal, then rerun this installer."
        }
        Write-Ok "Node $nodeVer (installed)"
    } else {
        Write-Ok "Node $nodeVer"
    }

    # 4. npm
    Write-Step "Checking npm"
    $npmVer = Get-CommandVersion 'npm'
    if (-not $npmVer) {
        Exit-WithError "npm not found after Node install." `
                      "Reinstall Node.js LTS from https://nodejs.org/"
    }
    Write-Ok "npm $npmVer"

    # 5. Dart Sass
    Write-Step "Checking Dart Sass (>= $($MinSassMajorMin[0]).$($MinSassMajorMin[1]))"
    $sassVer = Get-CommandVersion 'sass'
    $needSassInstall = $false
    if (-not $sassVer) {
        $needSassInstall = $true
        Write-Info "Sass not found. Installing via npm..."
    } else {
        $tuple = Extract-SemverTuple $sassVer
        if ($tuple[0] -lt $MinSassMajorMin[0] -or `
           ($tuple[0] -eq $MinSassMajorMin[0] -and $tuple[1] -lt $MinSassMajorMin[1])) {
            $needSassInstall = $true
            Write-Info "Found sass $sassVer, need >= $($MinSassMajorMin[0]).$($MinSassMajorMin[1]). Upgrading..."
        }
    }
    if ($needSassInstall) {
        & npm install -g sass
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "npm install -g sass failed (exit $LASTEXITCODE)." `
                          "Try running PowerShell as Administrator or run 'npm install -g sass' manually."
        }
        Refresh-EnvPath
        $sassVer = Get-CommandVersion 'sass'
        if (-not $sassVer) {
            $fallback = Join-Path $env:APPDATA 'npm\sass.cmd'
            if (Test-Path $fallback) { $sassVer = & $fallback --version 2>&1 | Out-String }
        }
    }
    Write-Ok "sass $sassVer"

    # 6. Deploy skills
    Write-Step "Deploying skills to $TargetSkillsDir"
    if (-not (Test-Path $SourceSkillsDir)) {
        Exit-WithError "Source skills folder missing: $SourceSkillsDir" `
                      "Re-download the package so that 'skills/<name>/SKILL.md' folders exist next to install.ps1."
    }

    $skillFolders = Get-ChildItem -Path $SourceSkillsDir -Directory
    if (-not $skillFolders -or $skillFolders.Count -eq 0) {
        Exit-WithError "No skills found under $SourceSkillsDir" `
                      "Each skill must live in its own subfolder with a SKILL.md inside."
    }

    $deployed = @()
    foreach ($sf in $skillFolders) {
        $skillName      = $sf.Name
        $targetSkillDir = Join-Path $TargetSkillsDir $skillName
        $sourceManifest = Join-Path $sf.FullName 'SKILL.md'
        if (-not (Test-Path $sourceManifest)) {
            Write-Warn2 "Skipping '$skillName' (no SKILL.md)"
            continue
        }

        $skipThis = $false
        if (Test-Path $targetSkillDir) {
            if (-not $Force) {
                $answer = Read-Host "    '$skillName' already installed. Overwrite? [y/N]"
                if ($answer -notmatch '^[yY]') {
                    Write-Info "Keeping existing '$skillName'. Skipping."
                    $skipThis = $true
                }
            }
            if (-not $skipThis) {
                Remove-Item -Recurse -Force $targetSkillDir
            }
        }

        if (-not $skipThis) {
            New-Item -ItemType Directory -Path $targetSkillDir -Force | Out-Null
            Copy-Item -Recurse -Force (Join-Path $sf.FullName '*') $targetSkillDir
            Write-Ok "Deployed /$skillName"
            $deployed += $skillName
        }
    }

    # 7. Self-test (compile skill only)
    Write-Step "Running self-test"
    $compileScript = Join-Path $TargetSkillsDir 'scss-compile\bin\compile-scss.ps1'
    if (-not (Test-Path $compileScript)) {
        Write-Warn2 "Skipping self-test: scss-compile not installed."
    }
    else {
        $testDir = Join-Path ([IO.Path]::GetTempPath()) "scss-compile-selftest-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $sassDir = Join-Path $testDir 'sass'
        New-Item -ItemType Directory -Path $sassDir -Force | Out-Null
        $testScss = Join-Path $sassDir 'selftest.scss'
        '$c: red; body { color: $c; }' | Set-Content -Path $testScss -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $compileScript -Path $testDir 2>&1 | ForEach-Object { Write-Info $_ }
        $selfTestExit = $LASTEXITCODE

        $outCss = Join-Path $testDir 'selftest.css'
        $outMin = Join-Path $testDir 'selftest.min.css'
        if ($selfTestExit -eq 0 -and (Test-Path $outCss) -and (Test-Path $outMin)) {
            Write-Ok "Self-test passed (compiled selftest.scss to .css + .min.css)"
        } else {
            Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
            Exit-WithError "Self-test failed (exit $selfTestExit). Skill installed but compilation is broken." `
                          "Inspect '$compileScript' and rerun with: powershell -File '$compileScript' -Path <path>"
        }
        Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
    }

    # 8. Summary
    Write-Host ""
    Write-Host "  Installation complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Skills     : $TargetSkillsDir"
    if ($deployed.Count -gt 0) {
        foreach ($s in $deployed) { Write-Host "    - /$s" }
    }
    Write-Host "  Node       : $nodeVer"
    Write-Host "  npm        : $npmVer"
    Write-Host "  sass       : $(($sassVer -split "`r?`n")[0])"
    Write-Host ""
    Write-Host "  Next step  : restart Claude Code, then use any of the installed skills." -ForegroundColor Cyan
    Write-Host ""
    exit 0
}
catch {
    Write-Host ""
    Write-Fail "Installation aborted: $($_.Exception.Message)"
    exit 1
}
