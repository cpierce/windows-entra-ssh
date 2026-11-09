# uninstall.ps1 -- remove the jump and the session server. Leaves the base OpenSSH setup (00).
# Run from the console or RDP, NOT over SSH: it stops the session server, which would end a
# session that came in through the jump before the cleanup finishes.
# Not yet exercised on a live machine -- read it before running.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Config

# 1. Stop sending admin logins through jump.ps1.
$bak = "$SshdConfig.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $SshdConfig $bak
(Get-Content $SshdConfig) | Where-Object { $_ -notmatch '^\s*ForceCommand .*jump\.ps1' } | Set-Content $SshdConfig -Encoding ascii
& (Join-Path $OpenSshBin 'sshd.exe') -t -f $SshdConfig
if ($LASTEXITCODE -ne 0) { Copy-Item $bak $SshdConfig -Force; throw 'sshd -t rejected the change; the previous sshd_config was restored.' }

# 2. The logon task and the running session server.
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Get-NetTCPConnection -State Listen -LocalPort $SessionPort -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force }

# 3. Files and the optional firewall rule.
Remove-Item $SessionDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $JumpScript, $JumpKey, "$JumpKey.pub" -Force -ErrorAction SilentlyContinue
Remove-NetFirewallRule -Name "usshd-$SessionPort" -ErrorAction SilentlyContinue

# 4. Put back the DefaultShell that 04 saved, if it still exists on disk.
$saved = Join-Path $SshDir 'DefaultShell.bak'
if (Test-Path $saved) {
    $prev = (Get-Content $saved -Raw).Trim()
    if ($prev -and (Test-Path $prev)) {
        Set-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $prev
        "DefaultShell restored to $prev"
    }
}
'Removed. Admin logins now get a plain elevated shell as the local admin.'
