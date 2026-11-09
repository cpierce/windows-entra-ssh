# 04-set-pwsh7-default-shell.ps1 -- optional: interactive SSH sessions open PowerShell 7.
# Needs the MSI build of PowerShell 7 (C:\Program Files\PowerShell\7\pwsh.exe). The Microsoft
# Store build is an app alias inside one user's profile and can't be the OpenSSH shell.
# Commands passed on the ssh command line still run in Windows PowerShell 5.1, because
# jump.ps1 calls powershell.exe for them. This does NOT make direct Entra key logins work.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Config

$pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
# A DefaultShell that doesn't exist makes sshd refuse EVERY login, so check first.
if (-not (Test-Path $pwsh)) {
    throw "Not found: $pwsh. Install the PowerShell 7 MSI from the PowerShell GitHub releases (winget may install the Store build instead)."
}
& $pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' | ForEach-Object { "pwsh runs: $_" }

$k   = 'HKLM:\SOFTWARE\OpenSSH'
$old = (Get-ItemProperty $k -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
Set-Content -Path (Join-Path $SshDir 'DefaultShell.bak') -Value "$old" -Encoding ascii
New-ItemProperty -Path $k -Name DefaultShell -Value $pwsh -PropertyType String -Force | Out-Null
"DefaultShell: $old  ->  $pwsh   (previous value saved in $SshDir\DefaultShell.bak)"
'Test with a NEW connection before closing this window:  ssh <admin>@<this-pc>'
