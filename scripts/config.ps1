# config.ps1 -- settings shared by every script in this folder.
# Replace the REPLACE values, then run the numbered scripts in order from an elevated
# Windows PowerShell 5.1 prompt on the Windows PC.

# The Entra ID (Azure AD) account whose desktop session SSH should land in, exactly as
# `whoami` prints it in that user's own session, e.g. 'AzureAD\JaneDoe'.
$EntraUser    = 'AzureAD\REPLACE_ME'
# That user's profile folder, e.g. 'C:\Users\JaneDoe'.
$EntraProfile = 'C:\Users\REPLACE_ME'

# Local administrator you SSH in as (key-only). `00-install-openssh.ps1 -WithLocalAdmin` creates it.
$AdminUser    = 'sshadmin'

# Public key(s) allowed to log in as $AdminUser: one string per key (the contents of your id_*.pub).
$AdminPublicKeys = @(
    'ssh-ed25519 AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY you@laptop'
)

# The second sshd that runs inside the Entra user's desktop session.
$SessionPort  = 2222
$SessionDir   = Join-Path $EntraProfile 'usshd'
$TaskName     = 'usshd-' + $EntraUser.Split('\')[-1].ToLower()

# Jump wiring. The jump key lives in the local admin's profile on the PC and never leaves it.
$AdminProfile = Join-Path $env:SystemDrive "Users\$AdminUser"
$JumpKey      = Join-Path $AdminProfile '.ssh\jump_ed25519'
$JumpScript   = 'C:\ProgramData\ssh\jump.ps1'

# Windows OpenSSH locations (inbox install).
$SshDir       = 'C:\ProgramData\ssh'
$SshdConfig   = Join-Path $SshDir 'sshd_config'
$OpenSshBin   = Join-Path $env:WINDIR 'System32\OpenSSH'

function Assert-Config {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this from an elevated PowerShell (Run as administrator).'
    }
    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'Run this in Windows PowerShell 5.1 (powershell.exe), which these scripts were tested with.'
    }
    if ("$EntraUser $EntraProfile $($AdminPublicKeys -join ' ')" -match 'REPLACE') {
        throw 'Edit config.ps1 first: replace every REPLACE value.'
    }
}
