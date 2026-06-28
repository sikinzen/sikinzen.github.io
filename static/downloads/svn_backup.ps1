# SVN Hotcopy Backup Script (PowerShell)
# ========================================
# Download from: https://sikinzen.github.io/downloads/svn_backup.ps1
# Usage: PowerShell -NoProfile -ExecutionPolicy Bypass -File svn_backup.ps1
#
# === BEFORE RUNNING: Modify the CONFIG section below ===

# ======================== CONFIG ========================
# !! CHANGE THESE VALUES TO MATCH YOUR ENVIRONMENT !!

# Root directory where your SVN repositories live
# Example: "D:\Repositories" or "C:\SVN\Repos"
$REPO_BASE         = "D:\Repositories"

# Directory where backups will be stored (MUST be a different disk!)
# Example: "E:\SVN_Backup"
$BACKUP_ROOT       = "E:\SVN_Backup"

# Number of days to keep old backups (older than this will be auto-deleted)
$RETENTION_DAYS    = 30

# Safety factor: backup will be skipped if free space < repo_size * factor
# Minimum recommended: 2 (meaning you need at least 2x the repo size free)
$SPACE_SAFETY_FACTOR = 2

# List of repository names to back up (subdirectory names under REPO_BASE)
# Example: @("MyProject", "AnotherRepo", "ThirdRepo")
$REPOS = @("repo1", "repo2", "repo3")

# ======================== INIT ========================
$ErrorActionPreference = "Stop"
$TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"
$LOG_DIR   = Join-Path $BACKUP_ROOT "logs"
$LOG_FILE  = Join-Path $LOG_DIR "backup_${TIMESTAMP}.log"

if (-not (Test-Path $LOG_DIR))   { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }
if (-not (Test-Path $BACKUP_ROOT)) { New-Item -ItemType Directory -Path $BACKUP_ROOT -Force | Out-Null }

$OverallSuccess = $true

function Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss.ff')] $Message"
    Write-Host $line
    Add-Content -Path $LOG_FILE -Value $line
}

function Get-FreeSpaceGB {
    param([string]$Drive)
    $Drive = $Drive.TrimEnd('\')
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'" -ErrorAction Stop
        return [math]::Round($disk.FreeSpace / 1GB, 2)
    } catch {
        try {
            $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$Drive'" -ErrorAction Stop
            return [math]::Round($disk.FreeSpace / 1GB, 2)
        } catch {
            return 0
        }
    }
}

function Get-RepoSizeGB {
    param([string]$RepoPath)
    try {
        $size = (Get-ChildItem -Path $RepoPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        return [math]::Round($size / 1GB, 2)
    } catch {
        return 0
    }
}

# ======================== MAIN ========================
Log "============================================================"
Log "SVN Backup Job Started"
Log "Time     : $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"
Log "Source   : $REPO_BASE"
Log "Target   : $BACKUP_ROOT"
Log "Retention: $RETENTION_DAYS days"
Log "============================================================"

# ---- Step 1: Clean old backups ----
Log ""
Log "[Step 1/3] Cleaning backups older than $RETENTION_DAYS days..."

$cutoff = (Get-Date).AddDays(-$RETENTION_DAYS)
$deleted = 0
Get-ChildItem -Path $BACKUP_ROOT -Directory | Where-Object {
    $_.Name -match '_' -and $_.LastWriteTime -lt $cutoff
} | ForEach-Object {
    Log "Deleting: $($_.FullName)"
    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    if ($?) { $deleted++ }
    else     { Log "[WARNING] Failed to delete: $($_.FullName)" }
}

if ($deleted -eq 0) {
    Log "No backups older than $RETENTION_DAYS days to clean."
} else {
    Log "Cleaned $deleted old backup(s)."
}

# ---- Step 2: Backup each repo ----
Log ""
Log "[Step 2/3] Starting repository backups..."

foreach ($repo in $REPOS) {
    $repoPath  = Join-Path $REPO_BASE $repo
    $backupPath = Join-Path $BACKUP_ROOT "${repo}_${TIMESTAMP}"

    Log "------------------------------------------------------------"
    Log "Repository: $repo"
    Log "Source    : $repoPath"
    Log "Target    : $backupPath"

    # Validate repo
    if (-not (Test-Path $repoPath)) {
        Log "[ERROR] Repository not found: $repoPath"
        $OverallSuccess = $false
        continue
    }
    if (-not (Test-Path (Join-Path $repoPath "format"))) {
        Log "[ERROR] Not a valid SVN repository (no format file)"
        $OverallSuccess = $false
        continue
    }

    # Show latest revision
    $youngest = & svnlook youngest $repoPath 2>$null
    if ($LASTEXITCODE -eq 0 -and $youngest) {
        Log "Latest revision: $youngest"
    } else {
        Log "[WARNING] Could not determine latest revision"
    }

    # Show repo size
    $repoSizeGB = Get-RepoSizeGB $repoPath
    Log "Repository size: ${repoSizeGB} GB"

    # Check disk space
    $drive = [System.IO.Path]::GetPathRoot($BACKUP_ROOT)
    $freeGB = Get-FreeSpaceGB $drive
    $requiredGB = [math]::Round($repoSizeGB * $SPACE_SAFETY_FACTOR, 2)
    Log "Free space  : ${freeGB} GB"
    Log "Required    : ${requiredGB} GB (repo x $SPACE_SAFETY_FACTOR)"

    if ($freeGB -lt $requiredGB) {
        Log "[ERROR] Insufficient disk space - skipping $repo"
        $OverallSuccess = $false
        continue
    }
    Log "[OK] Sufficient disk space"

    # Execute hotcopy
    Log "Starting hotcopy..."
    $backupStart = Get-Date

    $errorFile = Join-Path $LOG_DIR "hotcopy_error_${repo}.tmp"
    $result = & svnadmin hotcopy $repoPath $backupPath --clean-logs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $elapsed = [math]::Round(((Get-Date) - $backupStart).TotalSeconds, 1)
        Log "[OK] Hotcopy completed in ${elapsed}s"

        # Verify backup
        $formatFile = Join-Path $backupPath "format"
        if (Test-Path $formatFile) {
            $backupRev = & svnlook youngest $backupPath 2>$null
            Log "[OK] Backup verified - revision: $backupRev"
        } else {
            Log "[WARNING] Backup verification failed - no format file found"
        }
    } else {
        Log "[ERROR] Hotcopy FAILED with exit code $exitCode"
        if ($result) {
            Add-Content -Path $LOG_FILE -Value $result
        }
        Log "Error details written to log"

        # Clean up partial backup
        if (Test-Path $backupPath) {
            Remove-Item -Path $backupPath -Recurse -Force -ErrorAction SilentlyContinue
            Log "Cleaned up failed backup directory"
        }
        $OverallSuccess = $false
    }

    Log "------------------------------------------------------------"
}

# ---- Step 3: Summary ----
Log ""
Log "[Step 3/3] Backup Summary"
if ($OverallSuccess) {
    Log "RESULT: ALL BACKUPS COMPLETED SUCCESSFULLY"
} else {
    Log "RESULT: SOME BACKUPS FAILED - check log for details"
}
Log "============================================================"
Log "Backup Job Finished: $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"
Log "============================================================"
Log ""

exit 0
