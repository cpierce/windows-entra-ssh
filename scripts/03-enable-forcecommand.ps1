# 03-enable-forcecommand.ps1 -- send every login by $AdminUser through jump.ps1.
# Afterwards `ssh <admin>@<this-pc>` lands in the Entra user's elevated desktop session
# (or in a plain admin shell while they're logged off). Clients need no special config.
# Safe to re-run.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Config
if (-not (Test-Path $JumpScript)) { throw "Missing $JumpScript -- run 02 first." }

$bak = "$SshdConfig.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $SshdConfig $bak
$lines = [System.Collections.Generic.List[string]](Get-Content $SshdConfig)
if (-not ($lines | Where-Object { $_ -match '^\s*ForceCommand .*jump\.ps1' })) {
    $i = $lines.FindIndex([Predicate[string]]{ param($l) $l -match "^Match User $([regex]::Escape($AdminUser))\s*$" })
    if ($i -lt 0) { throw "No 'Match User $AdminUser' block in sshd_config -- run 00 first." }
    $lines.Insert($i + 1, "       ForceCommand powershell.exe -NoProfile -ExecutionPolicy Bypass -File $($JumpScript -replace '\\', '/')")
    Set-Content -Path $SshdConfig -Value $lines -Encoding ascii
}

# Validate; put the previous file back if sshd rejects it.
& (Join-Path $OpenSshBin 'sshd.exe') -t -f $SshdConfig
if ($LASTEXITCODE -ne 0) { Copy-Item $bak $SshdConfig -Force; throw 'sshd -t rejected the change; the previous sshd_config was restored.' }

Get-Content $SshdConfig | Select-String '^Match|AuthorizedKeysFile|ForceCommand|PasswordAuthentication' | ForEach-Object { $_.Line }

# In our testing (OpenSSH for Windows 9.5) the next connection picked up the change without a
# service restart. If you do restart sshd from inside an SSH session, spawn the restart via WMI:
# a child of your session would be killed along with it.
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
#       CommandLine = 'powershell.exe -NoProfile -Command Start-Sleep 2; Restart-Service sshd' }
"ForceCommand is on. Test from a client:  ssh $AdminUser@<this-pc> whoami"
