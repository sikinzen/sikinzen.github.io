# SVN Hotcopy Backup - Windows Task Scheduler Setup
# ===================================================
# Download from: https://sikinzen.github.io/downloads/setup_svn_backup_task.ps1
# Usage (run as Administrator): 
#   PowerShell -NoProfile -ExecutionPolicy Bypass -File setup_svn_backup_task.ps1
#
# === BEFORE RUNNING: Modify the CONFIG section below ===

# ======================== CONFIG ========================
# !! CHANGE THESE VALUES TO MATCH YOUR ENVIRONMENT !!

# Name shown in Windows Task Scheduler
$TaskName     = "SVN Hotcopy Backup"

# Full path to svn_backup.ps1 on your server
# Example: "D:\Scripts\svn_backup.ps1"
$ScriptPath   = "D:\Scripts\svn_backup.ps1"

# When to run (24-hour format)
# Default: 02:00 AM every Sunday
$ScheduleTime = "02:00"

# ======================== CREATE TASK ========================
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $ScheduleTime
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force

Write-Host "============================================================"
Write-Host "Scheduled task '$TaskName' created successfully."
Write-Host "Script : $ScriptPath"
Write-Host "Schedule: Weekly on Sunday at $ScheduleTime"
Write-Host "Run as : SYSTEM (highest privileges)"
Write-Host "============================================================"
Write-Host ""
Write-Host "To run now: Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "To test   : PowerShell -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
