# RepoNudge

**Gives you a nudge when one of your GitHub repos needs attention.**

When you have several projects, it's easy to miss that one has failing tests, finished work
that was never released, an issue someone opened weeks ago, or no license. RepoNudge checks all
your public repos in one go and tells you **what needs you and what to do about it**, in plain words.

On Windows it can also run quietly once a day and pop up a notification, **only when
something new comes up**, so it doesn't nag you about things you already know.

```text
[HIGH] polygraph: Last 'CI' run failed
        what to do: Open the Actions tab, read the failing step, fix it and push again.
[MEDIUM] StayGone: 3 commit(s) since release v0.2.0
        what to do: If those changes are finished, publish a new release (bump the version first).
[LOW] old-project: No changes for 140 days
        what to do: Check it still works (run its tests); archive it if you are done with it.
```

- Plain PowerShell: Windows PowerShell 5.1 (built into Windows) or PowerShell 7 on Linux/macOS.
  Nothing to install.
- Reads public GitHub information only. No account needed, no telemetry.

## What it checks

| Kind | Finding | Severity |
|---|---|---|
| `tests` | The last test run (GitHub Actions) failed | high |
| `security` | Open Dependabot security alerts (only with a token, see below) | high |
| `unreleased` | Commits made since the latest release | medium |
| `issues` | Open issues or pull requests waiting for you | medium |
| `readme` | No README | medium |
| `no-release` | Never released | low |
| `quiet` | No changes for 90+ days (adjustable) | low |
| `license` | No license file | low |
| `description` | No one-line description | low |

Forks, archived repos and your profile repo are skipped. GitHub's own automatic jobs
(dependency graph, Pages deploys) aren't counted as "tests".

## Quick start (Windows)

1. Click the green **Code** button on this page → **Download ZIP** → right-click it →
   **Extract All…** → **Extract**.
2. Open **Windows PowerShell** (no admin needed) and go to the folder, for example:

   ```powershell
   cd $HOME\Downloads\RepoNudge-main\RepoNudge-main
   ```

3. Check an account:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\RepoNudge.ps1 check -User your-github-name
   ```

To skip typing `-User` every time, add `user: your-github-name` to your config file
(`powershell -ExecutionPolicy Bypass -File .\RepoNudge.ps1 config` shows where it is).

On Linux/macOS with PowerShell 7: `pwsh ./RepoNudge.ps1 check -User your-github-name`

## Daily nudge (optional, Windows)

`nudge` runs the same check silently and only shows a notification for **new** problems.
To run it every day, create a task yourself in **Task Scheduler**:

1. Start → type **Task Scheduler** → open it → **Create Basic Task…**
2. Name it `RepoNudge` → **Daily** → pick a time → **Start a program**.
3. Program: `powershell.exe`
4. Arguments (use your own folder):
   `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\path\to\RepoNudge\RepoNudge.ps1" nudge`
5. **Finish**. To stop it later, delete the task in Task Scheduler.

## Commands

| Command | What it does |
|---|---|
| `check [-User name]` | Check now and list everything that needs you, with what to do |
| `nudge` | Quiet check; notification only for problems that weren't there last time |
| `config` | Show your config file |
| `about` | Version and author |

Options: `-QuietDays N` (default 90), `-Json` (machine-readable output).

## Config and ignore rules

Your config file lives in `%LOCALAPPDATA%\RepoNudge\config.txt` (Windows) or
`~/.reponudge/config.txt` (Linux/macOS), created from `config/config.example.txt`:

```text
user: your-github-name
quiet-days: 120
ignore: old-experiment            # skip a whole repo
ignore: my-notes|no-release       # this repo is never meant to be released
ignore: *|quiet                   # don't report quiet repos at all
```

## Security alerts and the GitHub limit (optional token)

Without signing in, GitHub allows **60 checks an hour per internet address**, enough for
about 12 repos. A shared connection (like a VPN) can use that up faster; RepoNudge then
tells you when to try again.

For more checks, and to include **security alerts**, give it a **read-only** token for the
current window only:

1. GitHub → your picture → **Settings** → **Developer settings** → **Personal access tokens** →
   **Fine-grained tokens** → **Generate new token**.
2. Set an **expiration** (e.g. 30 days), **Repository access: All repositories**, and under
   permissions give **read-only** access to **Dependabot alerts** and **Metadata**.
3. In PowerShell, for this session only:

   ```powershell
   $env:GITHUB_TOKEN = Read-Host "Paste token"   # not saved anywhere
   ```

Never put a token in a file inside this folder or commit it.

## Where RepoNudge keeps its files

`%LOCALAPPDATA%\RepoNudge\` (or `~/.reponudge/`): `config.txt`, `report.json` (last full
result), `last-findings.json` (what `nudge` already told you about). Delete the folder to reset.

## Running the tests

```powershell
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5 -SkipPublisherCheck
Invoke-Pester .\tests
```

The tests use made-up repo data only; they never contact GitHub.

## Inspiration and credit

Written from scratch; no code copied. Ideas came from:

- [github/stale-repos](https://github.com/github/stale-repos): flagging repos that have gone quiet.
- [gh-dash](https://github.com/dlvhdr/gh-dash): seeing all your GitHub work in one place.
- My own [StayGone](https://github.com/sopi22/StayGone): no-install PowerShell, and Windows
  notifications only when something actually changed.

What's different here: one plain command for *your own* repos, a "what to do" line for every
finding, and notifications that only fire for new problems.

## Author

Developed by **Jhoana Sophia C. Munar** ([@sopi22](https://github.com/sopi22)).

## License

[MIT](LICENSE) - Copyright (c) 2026 Jhoana Sophia C. Munar.
