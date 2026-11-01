<#
.SYNOPSIS
    RepoNudge - gives you a nudge when one of your GitHub repos needs attention.

.DESCRIPTION
    Checks your public GitHub repos for failing tests, unreleased work, quiet
    repos, waiting issues and missing basics, and tells you what to do about
    each one. On Windows it can pop up a notification, but only for NEW
    problems, so it doesn't nag.

    Copyright (c) 2026 Jhoana Sophia C. Munar. MIT License.
    https://github.com/sopi22/RepoNudge

.EXAMPLE
    .\RepoNudge.ps1 check -User sopi22     # check one account
    .\RepoNudge.ps1 check                  # uses the users in your config file
    .\RepoNudge.ps1 nudge                  # check quietly, notify only about new problems
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'nudge', 'config', 'about', 'help')]
    [string]$Command = 'help',

    [string[]]$User,
    [int]$QuietDays = 0,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/RepoNudge.psm1') -Force -DisableNameChecking

$dataDir = Get-RepoNudgeDataDir
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
$configPath = Join-Path $dataDir 'config.txt'
$statePath  = Join-Path $dataDir 'last-findings.json'
$reportPath = Join-Path $dataDir 'report.json'
if (-not (Test-Path $configPath)) { Copy-Item (Join-Path $PSScriptRoot 'config/config.example.txt') $configPath }

$cfg = ConvertFrom-RepoNudgeConfig -Lines (Get-Content $configPath)
$users = @($User | Where-Object { $_ })
if ($users.Count -eq 0) { $users = @($cfg.Users) }
if ($QuietDays -le 0) { $QuietDays = $cfg.QuietDays }

function Invoke-Check {
    if ($users.Count -eq 0) {
        Write-Host "No GitHub user given. Use -User <name>, or add 'user: <name>' to $configPath" -ForegroundColor Yellow
        exit 1
    }
    $all = @()
    foreach ($u in $users) {
        foreach ($repo in (Get-RepoNudgeRepos -User $u)) {
            $facts = Get-RepoNudgeFacts -Repo $repo
            $all += @(Get-RepoNudgeFindings -Facts $facts -QuietDays $QuietDays |
                      Where-Object { -not (Test-RepoNudgeIgnored -Finding $_ -Ignore $cfg.Ignore) })
        }
    }
    return ,$all
}

trap [System.InvalidOperationException] {
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 3
}

switch ($Command) {

    'check' {
        $findings = Invoke-Check
        ConvertTo-Json -InputObject @($findings) -Depth 3 | Set-Content -Path $reportPath -Encoding UTF8
        if ($Json) { ConvertTo-Json -InputObject @($findings) -Depth 3; break }
        if ($findings.Count -eq 0) {
            Write-Host "All your repos look fine. Nothing needs you right now." -ForegroundColor Green
        } else {
            $order = @{ high = 0; medium = 1; low = 2 }
            foreach ($f in ($findings | Sort-Object @{ e = { $order[$_.Severity] } }, Repo)) {
                $color = @{ high = 'Red'; medium = 'Yellow'; low = 'Gray' }[$f.Severity]
                Write-Host ("[{0}] {1}: {2}" -f $f.Severity.ToUpper(), $f.Repo, $f.Message) -ForegroundColor $color
                Write-Host ("        what to do: {0}" -f $f.Todo)
            }
            Write-Host ""
            Write-Host "$($findings.Count) thing(s) to look at. Report saved to $reportPath"
        }
        if (-not $env:GITHUB_TOKEN) { Write-Host "(Security alerts not checked: set GITHUB_TOKEN to a read-only token to include them.)" -ForegroundColor DarkGray }
    }

    'nudge' {
        # Meant for a daily scheduled run: silent unless something NEW appeared.
        $findings = Invoke-Check
        $previous = @()
        if (Test-Path $statePath) { try { $previous = @(Get-Content $statePath -Raw | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $previous = @() } }
        $new = @(Select-NewFindings -Findings $findings -PreviousKeys $previous)
        ConvertTo-Json -InputObject @($findings | ForEach-Object { Get-RepoNudgeKey $_ }) | Set-Content -Path $statePath -Encoding UTF8
        ConvertTo-Json -InputObject @($findings) -Depth 3 | Set-Content -Path $reportPath -Encoding UTF8
        $note = Format-RepoNudgeNotification -NewFindings $new
        if ($note) {
            $shown = Show-RepoNudgeNotification -Title $note.Title -Text $note.Text
            if (-not $shown) { Write-Host "$($note.Title) - $($note.Text)" }
        }
    }

    'config' {
        Write-Host "Config file: $configPath"
        Get-Content $configPath | ForEach-Object { Write-Host "  $_" }
    }

    'about' {
        Write-Host "$AppName $AppVersion"
        Write-Host "Developed by $Author"
        Write-Host $RepoUrl
        Write-Host "MIT License. Reads public GitHub data only; no telemetry."
    }

    default {
        Write-Host @"
$AppName $AppVersion - a nudge when one of your GitHub repos needs attention.

  check [-User name]   Check repos now and list what needs you, with what to do
  nudge                Quiet check; Windows notification only for NEW problems
  config               Show your config file (users, ignore rules, quiet days)
  about                Version and author

Options: -QuietDays N (default 90), -Json (machine-readable output)
"@
    }
}
