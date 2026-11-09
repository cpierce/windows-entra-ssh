# 00-install-openssh.ps1 -- Windows' built-in OpenSSH Server on port 22, key-only.
# Administrators who log in with a key get the full (elevated) token -- no UAC prompt.
#   -WithLocalAdmin  also creates $AdminUser (config.ps1) as a local administrator with a
#                    random password nobody knows; SSH logs it in by key only.
# Run from the console or RDP (it restarts sshd). Safe to re-run.
param([switch]$WithLocalAdmin)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Config

# 1. OpenSSH Server is a Windows capability (downloads from Windows Update).
if ((Get-WindowsCapability -Online -Name 'OpenSSH.Server*').State -ne 'Installed') {
    Write-Host 'Installing OpenSSH.Server...'
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
}

# 2. The first start generates sshd_config and the host keys.
if (-not (Test-Path $SshdConfig)) { Start-Service sshd; Start-Sleep 3; Stop-Service sshd }
$bak = "$SshdConfig.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $SshdConfig $bak

# 3. Top-level settings: port 22, no passwords, log to C:\ProgramData\ssh\logs\sshd.log.
#    The patterns are anchored at column 0 so they never touch the indented Match blocks.
$lines = @(Get-Content $SshdConfig)
$lines = $lines -replace '^#?Port\s+\d+.*', 'Port 22'
$lines = $lines -replace '^#?PasswordAuthentication\s+\w+.*', 'PasswordAuthentication no'
$lines = $lines -replace '^#?SyslogFacility\s+\w+.*', 'SyslogFacility LOCAL0'
if (-not ($lines -match '^PasswordAuthentication no')) { $lines = @('PasswordAuthentication no') + $lines }
if (-not ($lines -match '^SyslogFacility LOCAL0'))     { $lines = @('SyslogFacility LOCAL0') + $lines }

# 4. Replace the stock "Match Group administrators" block with per-user blocks.
#    Any "Match Group" makes sshd resolve the connecting user's groups BEFORE authentication.
#    For a cloud-only Entra account that needs an S4U token Windows can't create, so the
#    connection is reset -- even for password logins. Per-user Match blocks avoid that lookup.
$out = New-Object System.Collections.Generic.List[string]
$inGroupBlock = $false
foreach ($l in $lines) {
    if ($l -match '^\s*Match\s+Group\s+administrators\s*$') { $inGroupBlock = $true; continue }
    if ($inGroupBlock -and $l -match '^\s+\S') { continue }   # the block's indented lines
    $inGroupBlock = $false
    $out.Add($l)
}
$entra = $EntraUser.ToLower()
if (-not ($out | Where-Object { $_ -match "^Match User $([regex]::Escape($AdminUser))\s*$" })) {
    $out.Add('')
    $out.Add("Match User $AdminUser")
    $out.Add('       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys')
}
if (-not ($out | Where-Object { $_ -match "^Match User $([regex]::Escape($entra))\s*$" })) {
    # Optional: lets the Entra user log in on port 22 with their password (no jump involved).
    # Never give this user an AuthorizedKeysFile here -- see the README.
    $out.Add('')
    $out.Add("Match User $entra")
    $out.Add('       PasswordAuthentication yes')
}
Set-Content -Path $SshdConfig -Value $out -Encoding ascii
& (Join-Path $OpenSshBin 'sshd.exe') -t -f $SshdConfig
if ($LASTEXITCODE -ne 0) { Copy-Item $bak $SshdConfig -Force; throw 'sshd -t rejected the new sshd_config; the previous one was restored.' }

# 5. Keys that may log in as the admin. sshd ignores this file unless only
#    Administrators and SYSTEM can access it.
$ak = Join-Path $SshDir 'administrators_authorized_keys'
Set-Content -Path $ak -Value $AdminPublicKeys -Encoding ascii
icacls $ak /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

# 6. Windows PowerShell as the SSH login shell, unless one is already set (04 switches it to pwsh 7).
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
if (-not (Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue)) {
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -PropertyType String -Force `
        -Value (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null
}

# 7. Firewall rule (the capability ships it; make sure it exists and is on) + the service.
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
        -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
}
Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
Set-Service sshd -StartupType Automatic
Restart-Service sshd

# 8. Optional local admin for SSH (random password nobody knows; SSH is key-only).
if ($WithLocalAdmin -and -not (Get-LocalUser $AdminUser -ErrorAction SilentlyContinue)) {
    Add-Type -AssemblyName System.Web
    $pw = ConvertTo-SecureString ([System.Web.Security.Membership]::GeneratePassword(32, 8)) -AsPlainText -Force
    New-LocalUser $AdminUser -Password $pw -PasswordNeverExpires -AccountNeverExpires -Description 'SSH admin (key-only)' | Out-Null
    Add-LocalGroupMember -Group Administrators -Member $AdminUser
    Write-Host "Created local admin '$AdminUser' (key-only)."
}

# 9. A PC you SSH into shouldn't fall asleep on AC power (remove these two lines on a laptop).
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

Get-Service sshd | Format-Table Name, Status, StartType -AutoSize
Write-Host "Next: from your laptop run  ssh $AdminUser@<this-pc> whoami  once (it creates the admin's profile)."
