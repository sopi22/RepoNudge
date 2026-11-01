# Pester 5 tests for RepoNudge's decision logic. Fake data only: no network.
# Copyright (c) 2026 Jhoana Sophia C. Munar. MIT License.

BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'src', 'RepoNudge.psm1')) -Force -DisableNameChecking
    $now = [datetime]'2026-11-01'
    function New-Facts([hashtable]$Change = @{}) {
        $f = [ordered]@{
            Name = 'demo'; Description = 'A demo'; PushedAt = [datetime]'2026-10-20'; OpenIssues = 0
            HasReadme = $true; HasLicense = $true
            LatestRun = [pscustomobject]@{ Name = 'tests'; Status = 'completed'; Conclusion = 'success' }
            LatestRelease = 'v1.0.0'; Unreleased = 0; SecurityAlerts = $null
        }
        foreach ($k in $Change.Keys) { $f[$k] = $Change[$k] }
        [pscustomobject]$f
    }
    function Kinds($Facts) { @(Get-RepoNudgeFindings -Facts $Facts -Now $now | ForEach-Object Kind) }
}

Describe 'Get-RepoNudgeFindings' {
    It 'finds nothing for a healthy repo' {
        @(Kinds (New-Facts)).Count | Should -Be 0
    }
    It 'flags failing tests as high severity with a what-to-do line' {
        $f = @(Get-RepoNudgeFindings -Facts (New-Facts @{ LatestRun = [pscustomobject]@{ Name = 'CI'; Status = 'completed'; Conclusion = 'failure' } }) -Now $now)
        $f[0].Kind | Should -Be 'tests'
        $f[0].Severity | Should -Be 'high'
        $f[0].Todo | Should -Match 'Actions tab'
    }
    It 'ignores a run that is still in progress' {
        Kinds (New-Facts @{ LatestRun = [pscustomobject]@{ Name = 'CI'; Status = 'in_progress'; Conclusion = $null } }) | Should -Not -Contain 'tests'
    }
    It 'flags unreleased commits only when there are some' {
        Kinds (New-Facts @{ Unreleased = 3 }) | Should -Contain 'unreleased'
        Kinds (New-Facts @{ Unreleased = 0 }) | Should -Not -Contain 'unreleased'
    }
    It 'flags a repo that was never released' {
        Kinds (New-Facts @{ LatestRelease = $null; Unreleased = $null }) | Should -Contain 'no-release'
    }
    It 'flags open issues and missing basics' {
        $k = Kinds (New-Facts @{ OpenIssues = 2; HasReadme = $false; HasLicense = $false; Description = '' })
        $k | Should -Contain 'issues'
        $k | Should -Contain 'readme'
        $k | Should -Contain 'license'
        $k | Should -Contain 'description'
    }
    It 'flags a quiet repo after the chosen number of days' {
        $old = New-Facts @{ PushedAt = [datetime]'2026-06-01' }
        @(Get-RepoNudgeFindings -Facts $old -Now $now -QuietDays 90 | ForEach-Object Kind) | Should -Contain 'quiet'
        @(Get-RepoNudgeFindings -Facts $old -Now $now -QuietDays 365 | ForEach-Object Kind) | Should -Not -Contain 'quiet'
    }
    It 'reports security alerts only when they were checked' {
        Kinds (New-Facts @{ SecurityAlerts = 2 }) | Should -Contain 'security'
        Kinds (New-Facts @{ SecurityAlerts = $null }) | Should -Not -Contain 'security'
    }
}

Describe 'New vs old findings' {
    It 'only returns findings that were not there last time' {
        $a = New-RepoNudgeFinding 'r1' 'tests' 'high' 'x' 'y'
        $b = New-RepoNudgeFinding 'r2' 'issues' 'medium' 'x' 'y'
        $new = @(Select-NewFindings -Findings @($a, $b) -PreviousKeys @('r1|tests'))
        $new.Count | Should -Be 1
        $new[0].Repo | Should -Be 'r2'
    }
    It 'builds a notification only when something is new' {
        Format-RepoNudgeNotification -NewFindings @() | Should -BeNullOrEmpty
        $n = Format-RepoNudgeNotification -NewFindings @(
            (New-RepoNudgeFinding 'r2' 'quiet' 'low' 'No changes for 100 days' 'y'),
            (New-RepoNudgeFinding 'r1' 'tests' 'high' 'Last run failed' 'y'))
        $n.Title | Should -Be 'RepoNudge: 2 repos need(s) you'
        $n.Text | Should -Match '^r1: Last run failed'
    }
}

Describe 'Config and ignore rules' {
    It 'reads users, ignore rules and quiet days' {
        $c = ConvertFrom-RepoNudgeConfig -Lines @('# comment', 'user: sopi22', 'user: other', 'ignore: old-repo', 'ignore: *|quiet', 'quiet-days: 120')
        $c.Users | Should -Be @('sopi22', 'other')
        $c.Ignore | Should -Be @('old-repo', '*|quiet')
        $c.QuietDays | Should -Be 120
    }
    It 'applies whole-repo, per-kind and everywhere rules' {
        $f = New-RepoNudgeFinding 'demo' 'quiet' 'low' 'x' 'y'
        Test-RepoNudgeIgnored -Finding $f -Ignore @('demo') | Should -BeTrue
        Test-RepoNudgeIgnored -Finding $f -Ignore @('demo|quiet') | Should -BeTrue
        Test-RepoNudgeIgnored -Finding $f -Ignore @('*|quiet') | Should -BeTrue
        Test-RepoNudgeIgnored -Finding $f -Ignore @('demo|tests', 'other') | Should -BeFalse
    }
}
