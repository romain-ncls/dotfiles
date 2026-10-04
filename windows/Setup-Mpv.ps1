# Point Windows' mpv config at the dotfiles repo, so Windows and Arch read the
# very same files (mpv/ in the repo). Run once, in a normal (non-admin)
# PowerShell, after cloning the repo:
#
#   winget install Git.Git
#   git clone https://github.com/romain-ncls/dotfiles $HOME\dotfiles
#   powershell -ExecutionPolicy Bypass -File $HOME\dotfiles\windows\Setup-Mpv.ps1
#
# %APPDATA%\mpv becomes a directory junction to <repo>\mpv. The current folder
# is kept as mpv.backup-<date> next to it. mpv's state (watch_later, the
# sub-style choice, cache) lives in %LOCALAPPDATA%\mpv and is not touched.

$ErrorActionPreference = 'Stop'

$repo   = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'mpv'
$target = Join-Path $env:APPDATA 'mpv'

if (-not (Test-Path (Join-Path $source 'mpv.conf'))) {
    throw "No mpv.conf in $source - is this script inside the dotfiles repo?"
}

$existing = Get-Item $target -ErrorAction SilentlyContinue
if ($existing -and $existing.LinkType -eq 'Junction') {
    if ($existing.Target -contains $source) {
        Write-Host "Already done: $target -> $source"
        exit 0
    }
    Remove-Item $target          # removes the junction only, not what it points to
} elseif ($existing) {
    $backup = "$target.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Rename-Item $target (Split-Path -Leaf $backup)
    Write-Host "Previous config kept in $backup"
}

New-Item -ItemType Junction -Path $target -Target $source | Out-Null
Write-Host "Done: $target -> $source"
