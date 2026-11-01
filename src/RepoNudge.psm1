# RepoNudge - gives you a nudge when one of your GitHub repos needs attention.
# Copyright (c) 2026 Jhoana Sophia C. Munar. MIT License.
#
# Same layout as StayGone: the decisions (what counts as a problem, what to
# tell the user) are pure functions that take plain data, so they can be
# tested without the network. Only the functions at the bottom call GitHub
# or show notifications.

Set-StrictMode -Version 2.0

$script:AppName    = 'RepoNudge'
$script:AppVersion = '0.1.0'
$script:Author     = 'Jhoana Sophia C. Munar'
$script:RepoUrl    = 'https://github.com/sopi22/RepoNudge'
$script:ApiBase    = 'https://api.github.com'

# ---------------------------------------------------------------- paths

function Get-RepoNudgeDataDir {
    if ($env:REPONUDGE_DATA_DIR) { return $env:REPONUDGE_DATA_DIR }
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'RepoNudge') }
    return (Join-Path $HOME '.reponudge')
}

# ---------------------------------------------------------- pure logic

function New-RepoNudgeFinding {
    param([string]$Repo, [string]$Kind, [string]$Severity, [string]$Message, [string]$Todo)
    [pscustomobject]@{ Repo = $Repo; Kind = $Kind; Severity = $Severity; Message = $Message; Todo = $Todo }
}

function Get-RepoNudgeFindings {
    <# Turns facts about one repo into findings. -Facts is a plain object:
         Name, Description, PushedAt (datetime), OpenIssues, HasReadme, HasLicense,
         LatestRun (object with Conclusion, Status, Name, or $null),
         LatestRelease (tag string or $null), Unreleased (int or $null),
         SecurityAlerts (int, or $null when not checked)
       -Now and -QuietDays make the "quiet repo" rule testable. #>
    param(
        [Parameter(Mandatory)][object]$Facts,
        [datetime]$Now = (Get-Date),
        [int]$QuietDays = 90
    )
    $r = $Facts.Name
    $out = @()

    if ($Facts.LatestRun -and $Facts.LatestRun.Status -eq 'completed' -and
        $Facts.LatestRun.Conclusion -in @('failure', 'timed_out', 'startup_failure')) {
        $out += New-RepoNudgeFinding $r 'tests' 'high' "Last '$($Facts.LatestRun.Name)' run failed" 'Open the Actions tab, read the failing step, fix it and push again.'
    }
    if ($null -ne $Facts.SecurityAlerts -and $Facts.SecurityAlerts -gt 0) {
        $out += New-RepoNudgeFinding $r 'security' 'high' "$($Facts.SecurityAlerts) open security alert(s)" 'Open Security > Dependabot alerts and update the listed packages.'
    }
    if ($Facts.LatestRelease -and $null -ne $Facts.Unreleased -and $Facts.Unreleased -gt 0) {
        $out += New-RepoNudgeFinding $r 'unreleased' 'medium' "$($Facts.Unreleased) commit(s) since release $($Facts.LatestRelease)" 'If those changes are finished, publish a new release (bump the version first).'
    }
    if (-not $Facts.LatestRelease) {
        $out += New-RepoNudgeFinding $r 'no-release' 'low' 'Never released' 'Publish a first release (e.g. v0.1.0) so people can see a finished version.'
    }
    if ($Facts.OpenIssues -gt 0) {
        $out += New-RepoNudgeFinding $r 'issues' 'medium' "$($Facts.OpenIssues) open issue(s)/pull request(s)" 'Reply to or close them; people are waiting for an answer.'
    }
    if ($Facts.PushedAt) {
        $days = [int][math]::Floor(($Now - [datetime]$Facts.PushedAt).TotalDays)
        if ($days -gt $QuietDays) {
            $out += New-RepoNudgeFinding $r 'quiet' 'low' "No changes for $days days" 'Check it still works (run its tests); archive it if you are done with it.'
        }
    }
    if (-not $Facts.HasReadme)  { $out += New-RepoNudgeFinding $r 'readme' 'medium' 'No README' 'Add a README: what it does, how to run it.' }
    if (-not $Facts.HasLicense) { $out += New-RepoNudgeFinding $r 'license' 'low' 'No license' 'Add a LICENSE file (MIT is a common choice) so others may use it.' }
    if (-not $Facts.Description) { $out += New-RepoNudgeFinding $r 'description' 'low' 'No description' 'Add a one-line description in the repo About box.' }
    return $out
}

function Get-RepoNudgeKey {
    <# Stable identity of a finding, used to tell new problems from old ones. #>
    param([Parameter(Mandatory)][object]$Finding)
    return "$($Finding.Repo)|$($Finding.Kind)"
}

function Select-NewFindings {
    <# Findings whose key wasn't in the previous run. #>
    param([object[]]$Findings = @(), [string[]]$PreviousKeys = @())
    return @($Findings | Where-Object { $PreviousKeys -notcontains (Get-RepoNudgeKey $_) })
}

function Test-RepoNudgeIgnored {
    <# Ignore rules: "repo" ignores a whole repo, "repo|kind" ignores one kind
       of finding for it, "*|kind" ignores that kind everywhere. #>
    param([object]$Finding, [string[]]$Ignore = @())
    foreach ($rule in $Ignore) {
        $parts = $rule.Split('|')
        if ($parts.Count -eq 1 -and $parts[0] -ieq $Finding.Repo) { return $true }
        if ($parts.Count -eq 2 -and ($parts[0] -eq '*' -or $parts[0] -ieq $Finding.Repo) -and $parts[1] -ieq $Finding.Kind) { return $true }
    }
    return $false
}

function ConvertFrom-RepoNudgeConfig {
    <# Reads config lines: "user: name", "ignore: repo" or "ignore: repo|kind",
       "quiet-days: 120". '#' starts a comment. #>
    param([string[]]$Lines)
    $cfg = [pscustomobject]@{ Users = @(); Ignore = @(); QuietDays = 90 }
    foreach ($line in $Lines) {
        $clean = ($line -replace '#.*$', '').Trim()
        if ($clean -match '^user\s*:\s*(\S+)$') { $cfg.Users += $Matches[1] }
        elseif ($clean -match '^ignore\s*:\s*(\S+)$') { $cfg.Ignore += $Matches[1] }
        elseif ($clean -match '^quiet-days\s*:\s*(\d+)$') { $cfg.QuietDays = [int]$Matches[1] }
    }
    return $cfg
}

function Format-RepoNudgeNotification {
    param([object[]]$NewFindings = @())
    if ($NewFindings.Count -eq 0) { return $null }
    $repos = @($NewFindings | ForEach-Object { $_.Repo } | Sort-Object -Unique)
    $first = $NewFindings | Sort-Object @{ e = { @{ high = 0; medium = 1; low = 2 }[$_.Severity] } } | Select-Object -First 1
    $noun = 'repo'
    if ($repos.Count -gt 1) { $noun = 'repos' }
    [pscustomobject]@{
        Title = "RepoNudge: $($repos.Count) $noun need(s) you"
        Text  = "$($first.Repo): $($first.Message). Run 'RepoNudge.ps1 check' for details."
    }
}

# ------------------------------------------------------- system helpers

function Invoke-RepoNudgeApi {
    <# GET from the GitHub API. Uses $env:GITHUB_TOKEN only if set (read-only,
       never written anywhere). Returns $null on 404, throws on other errors. #>
    param([Parameter(Mandatory)][string]$Path)
    $headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'RepoNudge' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
    try {
        return Invoke-RestMethod -Uri "$($script:ApiBase)/$Path" -Headers $headers -ErrorAction Stop
    } catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if (($code -eq 404) -or (($code -eq 403) -and ($Path -like '*dependabot*'))) { return $null }
        if (($code -eq 403 -or $code -eq 429) -and "$($_.ErrorDetails.Message)$($_.Exception.Message)" -match 'rate limit') {
            throw [System.InvalidOperationException]::new((Get-RepoNudgeRateLimitMessage))
        }
        throw
    }
}

function Get-RepoNudgeRateLimitMessage {
    <# Friendly explanation when GitHub's hourly limit is used up. Asking
       for the limit itself doesn't count against it. #>
    $when = 'in up to an hour'
    try {
        $rl = Invoke-RestMethod -Uri "$($script:ApiBase)/rate_limit" -Headers @{ 'User-Agent' = 'RepoNudge' } -ErrorAction Stop
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([int64]$rl.resources.core.reset).LocalDateTime
        $when = "after $($reset.ToString('HH:mm'))"
    } catch { }
    return ("GitHub's hourly limit for checks without signing in (60 per internet address) is used up. " +
            "Try again $when, or set GITHUB_TOKEN to a read-only token for 5000 checks an hour. " +
            "A shared connection such as a VPN can use up the limit faster.")
}

function Get-RepoNudgeFacts {
    <# Collects the facts Get-RepoNudgeFindings needs for one repo. #>
    param([Parameter(Mandatory)][object]$Repo)
    $full = $Repo.full_name
    $run = $null
    $runs = Invoke-RepoNudgeApi "repos/$full/actions/runs?per_page=10&branch=$($Repo.default_branch)"
    if ($runs -and $runs.workflow_runs) {
        # Skip GitHub's own automatic jobs; we want the project's tests.
        $real = @($runs.workflow_runs | Where-Object { $_.name -notmatch 'Dependency Graph|pages-build-deployment|Dependabot' })
        if ($real.Count) { $run = [pscustomobject]@{ Name = $real[0].name; Status = $real[0].status; Conclusion = $real[0].conclusion } }
    }
    $release = Invoke-RepoNudgeApi "repos/$full/releases/latest"
    $tag = $null; $ahead = $null
    if ($release) {
        $tag = $release.tag_name
        $cmp = Invoke-RepoNudgeApi "repos/$full/compare/$($tag)...$($Repo.default_branch)"
        if ($cmp) { $ahead = [int]$cmp.ahead_by }
    }
    $alerts = $null
    if ($env:GITHUB_TOKEN) {
        $a = Invoke-RepoNudgeApi "repos/$full/dependabot/alerts?state=open&per_page=100"
        if ($null -ne $a) { $alerts = @($a).Count }
    }
    [pscustomobject]@{
        Name = $Repo.name; Description = $Repo.description
        PushedAt = [datetime]$Repo.pushed_at; OpenIssues = [int]$Repo.open_issues_count
        HasReadme = [bool](Invoke-RepoNudgeApi "repos/$full/readme")
        HasLicense = [bool]$Repo.license
        LatestRun = $run; LatestRelease = $tag; Unreleased = $ahead; SecurityAlerts = $alerts
    }
}

function Get-RepoNudgeRepos {
    <# A user's own public repos (no forks, no archived ones, no profile repo). #>
    param([Parameter(Mandatory)][string]$User)
    $repos = Invoke-RepoNudgeApi "users/$User/repos?per_page=100&type=owner&sort=pushed"
    return @($repos | Where-Object { -not $_.fork -and -not $_.archived -and $_.name -ine $User })
}

function Show-RepoNudgeNotification {
    <# Windows notification via the built-in WinRT API; does nothing elsewhere. #>
    param([string]$Title, [string]$Text)
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { return $false }
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $nodes = $template.GetElementsByTagName('text')
        $null = $nodes.Item(0).AppendChild($template.CreateTextNode($Title))
        $null = $nodes.Item(1).AppendChild($template.CreateTextNode($Text))
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
            [Windows.UI.Notifications.ToastNotification]::new($template))
        return $true
    } catch { return $false }
}

Export-ModuleMember -Function * -Variable AppName, AppVersion, Author, RepoUrl
