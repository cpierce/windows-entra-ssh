# 01-install-session-sshd.ps1 -- a second sshd that runs INSIDE the Entra user's desktop session.
# It runs as that user, in their already-logged-on session, so it already holds their token:
# public-key logins work, and Windows is never asked for the S4U token it can't create.
# A logon task starts it with LogonType Interactive (uses the session's token, stores no
# password) and RunLevel Highest (elevated, if the user is a local administrator).
#   -OpenFirewall  also allow direct LAN connections to the session port. The jump doesn't
#                  need this; it only connects to 127.0.0.1.
# Run while the Entra user is logged on, from the console/RDP (not through the jump: this
# restarts the session server). Safe to re-run.
param([switch]$OpenFirewall)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Config

# 1. Config folder inside the user's profile (inherits SYSTEM + Administrators + the user).
New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null

# 2. Reuse the main sshd's ED25519 host key, so clients see the same fingerprint on both ports.
Copy-Item (Join-Path $SshDir 'ssh_host_ed25519_key') (Join-Path $SessionDir 'host') -Force

# 3. Keys allowed into the session server (02 appends the jump key).
$ak = Join-Path $SessionDir 'authorized_keys'
if (-not (Test-Path $ak)) { Set-Content -Path $ak -Value $AdminPublicKeys -Encoding ascii }

# 4. Its sshd_config. (StrictModes isn't supported by OpenSSH for Windows, so it's left out.)
$fwd = $SessionDir -replace '\\', '/'
Set-Content -Path (Join-Path $SessionDir 'sshd_config') -Encoding ascii -Value @(
    "Port $SessionPort"
    "HostKey $fwd/host"
    "AuthorizedKeysFile $fwd/authorized_keys"
)

# 5. Hidden launcher. It waits on sshd, so the task's restart policy notices a crash.
$exe = Join-Path $OpenSshBin 'sshd.exe'
$cfg = Join-Path $SessionDir 'sshd_config'
Set-Content -Path (Join-Path $SessionDir 'start.vbs') -Encoding ascii -Value @(
    'Set sh = CreateObject("WScript.Shell")'
    ('WScript.Quit sh.Run("""' + $exe + '"" -f ""' + $cfg + '""", 0, True)')
)

# 6. Logon task: runs as the user, in their own session, with their highest privileges.
$a = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\wscript.exe') `
        -Argument ('"' + (Join-Path $SessionDir 'start.vbs') + '"')
$t = New-ScheduledTaskTrigger -AtLogOn -User $EntraUser
$p = New-ScheduledTaskPrincipal -UserId $EntraUser -LogonType Interactive -RunLevel Highest
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 5 `
        -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null

# 7. Optional firewall rule for direct LAN access to the session port.
if ($OpenFirewall -and -not (Get-NetFirewallRule -Name "usshd-$SessionPort" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "usshd-$SessionPort" -DisplayName "user sshd $SessionPort" `
        -Direction Inbound -Protocol TCP -LocalPort $SessionPort -Action Allow -Profile Private | Out-Null
}

# 8. (Re)start it now: stop whatever holds the port, then run the task in the user's session.
$old = @(Get-NetTCPConnection -State Listen -LocalPort $SessionPort -ErrorAction SilentlyContinue |
         Select-Object -ExpandProperty OwningProcess -Unique)
foreach ($id in $old) { Stop-Process -Id $id -Force }
Start-Sleep 1
Start-ScheduledTask -TaskName $TaskName
Start-Sleep 4

$l = Get-NetTCPConnection -State Listen -LocalPort $SessionPort -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $l) { throw "Nothing is listening on port $SessionPort. Is $EntraUser logged on? The task also starts at their next logon." }
$proc  = Get-CimInstance Win32_Process -Filter "ProcessId=$($l.OwningProcess)"
$owner = Invoke-CimMethod -InputObject $proc -MethodName GetOwner
"Session server on port ${SessionPort}: pid $($l.OwningProcess), running as $($owner.Domain)\$($owner.User)"
