#Requires -Version 5.1
<#
.SYNOPSIS
    EasyClaw CLI — manage your OpenClaw installation on Windows

.DESCRIPTION
    EasyClaw is a post-install management tool for OpenClaw on Windows.
    It supports both bare-metal (npm/Node) and Docker installations.
    Commands: status, update, backup, restore, channels, logs, doctor,
              restart, stop, start, uninstall, help, version

.EXAMPLE
    .\easyclaw.ps1 status
    .\easyclaw.ps1 update
    .\easyclaw.ps1 backup
    .\easyclaw.ps1 restore
    .\easyclaw.ps1 logs -Lines 100
    .\easyclaw.ps1 channels list
    .\easyclaw.ps1 uninstall
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Args2
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIG
# ─────────────────────────────────────────────────────────────────────────────

$script:EASYCLAW_VERSION  = "1.0.0"
$script:EASYCLAW_DIR      = Join-Path $env:USERPROFILE ".easyclaw"
$script:OPENCLAW_DIR      = Join-Path $env:USERPROFILE ".openclaw"
$script:BACKUP_DIR        = Join-Path $script:EASYCLAW_DIR "backups"
$script:LOG_FILE          = Join-Path $env:TEMP "easyclaw.log"
$script:MAX_BACKUPS       = 5
$script:GITHUB_RELEASES   = "https://api.github.com/repos/openclaw/openclaw/releases/latest"

# Detect install mode once at startup
$script:INSTALL_MODE = "native"
$_composeFile = Join-Path $script:EASYCLAW_DIR "docker-compose.yml"
if (Test-Path $_composeFile) {
    $script:INSTALL_MODE = "docker"
}

# ─────────────────────────────────────────────────────────────────────────────
#  LOGGING HELPER
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    try {
        Add-Content -Path $script:LOG_FILE -Value $line -ErrorAction SilentlyContinue
    } catch {
        # Silently ignore log write failures — never crash the user's session
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  COLOR / UI  (Unicode box-drawing, colored console output)
# ─────────────────────────────────────────────────────────────────────────────

# Try to enable UTF-8 output on older consoles
if ($PSVersionTable.PSVersion.Major -ge 6) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} else {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Log $Message "INFO"
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
    Write-Log $Message "SUCCESS"
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor Yellow
    Write-Log $Message "WARN"
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "  [XX] $Message" -ForegroundColor Red
    Write-Log $Message "ERROR"
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "  --> $Message" -ForegroundColor Magenta
    Write-Log "STEP: $Message" "STEP"
}

function Write-Box {
    param(
        [string]$Title,
        [string[]]$Lines,
        [ConsoleColor]$BorderColor = [ConsoleColor]::DarkCyan
    )
    # Determine box width
    $maxLen = ($Lines | Measure-Object -Property Length -Maximum).Maximum
    if ($Title.Length -gt $maxLen) { $maxLen = $Title.Length }
    $width = $maxLen + 4   # 2 spaces padding each side

    $hBar   = [string]::new([char]0x2500, $width)
    $top    = [string][char]0x250C + $hBar + [string][char]0x2510
    $bottom = [string][char]0x2514 + $hBar + [string][char]0x2518
    $sep    = [string][char]0x251C + $hBar + [string][char]0x2524
    $side   = [string][char]0x2502

    Write-Host ""
    Write-Host "  $top" -ForegroundColor $BorderColor
    # Title row
    $pad   = $width - $Title.Length - 2
    $lPad  = [string]::new(' ', [math]::Floor($pad / 2))
    $rPad  = [string]::new(' ', [math]::Ceiling($pad / 2))
    Write-Host "  $side $lPad" -ForegroundColor $BorderColor -NoNewline
    Write-Host $Title -ForegroundColor White -NoNewline
    Write-Host "$rPad $side" -ForegroundColor $BorderColor
    Write-Host "  $sep" -ForegroundColor $BorderColor

    foreach ($line in $Lines) {
        $padAmount = $maxLen - $line.Length
        $rPadLine = $(if ($padAmount -gt 0) { [string]::new(' ', $padAmount) } else { '' })
        Write-Host "  $side  " -ForegroundColor $BorderColor -NoNewline
        Write-Host "$line$rPadLine" -NoNewline
        Write-Host "  $side" -ForegroundColor $BorderColor
    }
    Write-Host "  $bottom" -ForegroundColor $BorderColor
    Write-Host ""
}

function Show-Spinner {
    param(
        [ScriptBlock]$ScriptBlock,
        [string]$Label = "Working"
    )
    $frames = @("|", "/", "-", "\")
    $i      = 0

    # Run job in background
    $job = Start-Job -ScriptBlock $ScriptBlock

    while ($job.State -eq "Running") {
        $frame = $frames[$i % $frames.Length]
        Write-Host "`r  [$frame] $Label..." -NoNewline
        Start-Sleep -Milliseconds 120
        $i++
    }

    # Clear the spinner line
    Write-Host "`r" -NoNewline
    Write-Host ("  " + [string]::new(' ', ($Label.Length + 12))) -NoNewline
    Write-Host "`r" -NoNewline

    $result = Receive-Job $job -ErrorVariable jobErr 2>&1
    Remove-Job $job -Force
    if ($jobErr) { throw $jobErr }
    return $result
}

# ─────────────────────────────────────────────────────────────────────────────
#  UTILITY HELPERS
# ─────────────────────────────────────────────────────────────────────────────

function Get-InstalledVersion {
    <# Returns the installed openclaw version string, or $null on failure. #>
    try {
        if ($script:INSTALL_MODE -eq "docker") {
            $out = docker exec openclaw openclaw --version 2>$null
        } else {
            $out = & openclaw --version 2>$null
        }
        if ($out -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch {}
    return $null
}

function Get-ConfigPath {
    return Join-Path $script:OPENCLAW_DIR "openclaw.json"
}

function Read-OpenClawConfig {
    <# Returns a hashtable from openclaw.json, or $null. #>
    $cfgPath = Get-ConfigPath
    if (-not (Test-Path $cfgPath)) { return $null }
    try {
        $raw = Get-Content $cfgPath -Raw -Encoding UTF8
        return $raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-GatewayRunning {
    <# Returns $true if the OpenClaw gateway process or container is live. #>
    if ($script:INSTALL_MODE -eq "docker") {
        try {
            $status = docker inspect --format "{{.State.Running}}" openclaw 2>$null
            return ($status -eq "true")
        } catch { return $false }
    } else {
        $proc = Get-Process -Name "openclaw" -ErrorAction SilentlyContinue
        return ($null -ne $proc)
    }
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    return [math]::Round($size / 1MB, 2)
}

function Confirm-Prompt {
    param([string]$Question)
    Write-Host ""
    $resp = Read-Host "  $Question [Y/N]"
    return ($resp -match '^[Yy]')
}

function Ensure-Dirs {
    foreach ($d in @($script:EASYCLAW_DIR, $script:BACKUP_DIR)) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: STATUS
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Status {
    Write-Step "OpenClaw Status"

    # --- Installed version ---
    $version = Get-InstalledVersion
    if ($version) {
        Write-Success "OpenClaw version : $version"
    } else {
        Write-Warn "OpenClaw version : not detected"
    }

    # --- Gateway status ---
    $running = Test-GatewayRunning
    if ($running) {
        Write-Success "Gateway          : running"
    } else {
        Write-Warn "Gateway          : stopped"
    }

    # --- Process info ---
    if ($script:INSTALL_MODE -eq "docker") {
        Write-Info "Install mode     : docker"
        try {
            $stats = docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>$null |
                     Where-Object { $_ -match "openclaw" }
            if ($stats) {
                Write-Info "Container stats  : $stats"
            }
        } catch {}
    } else {
        Write-Info "Install mode     : native"
        $proc = Get-Process -Name "openclaw" -ErrorAction SilentlyContinue
        if ($proc) {
            $cpu = [math]::Round($proc.CPU, 2)
            $mem = [math]::Round($proc.WorkingSet64 / 1MB, 1)
            Write-Info "Process PID      : $($proc.Id)  CPU: ${cpu}s  RAM: ${mem} MB"
        }
    }

    # --- Connected channels ---
    $cfg = Read-OpenClawConfig
    if ($cfg -and $cfg.channels) {
        $chList = ($cfg.channels | ForEach-Object { $_.name }) -join ", "
        Write-Info "Channels         : $chList"
    } else {
        Write-Info "Channels         : (none configured)"
    }

    # --- Disk usage ---
    $diskMB = Get-FolderSizeMB $script:OPENCLAW_DIR
    Write-Info "Disk usage       : ${diskMB} MB  ($script:OPENCLAW_DIR)"

    # --- Last backup ---
    Ensure-Dirs
    $lastBackup = Get-ChildItem $script:BACKUP_DIR -Filter "*.zip" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1
    if ($lastBackup) {
        Write-Info "Last backup      : $($lastBackup.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) — $($lastBackup.Name)"
    } else {
        Write-Warn "Last backup      : never  (run: easyclaw backup)"
    }

    # --- Health verdict ---
    Write-Host ""
    if ($running -and $version) {
        Write-Host "  Health         : " -NoNewline
        Write-Host "HEALTHY" -ForegroundColor Green
    } elseif ($version -and -not $running) {
        Write-Host "  Health         : " -NoNewline
        Write-Host "DEGRADED (gateway not running)" -ForegroundColor Yellow
    } else {
        Write-Host "  Health         : " -NoNewline
        Write-Host "UNKNOWN (openclaw not detected)" -ForegroundColor Red
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: UPDATE
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Update {
    Write-Step "Checking for OpenClaw updates"

    # Fetch latest release from GitHub
    $latestVersion = $null
    $releaseNotes  = $null
    try {
        $headers = @{ "User-Agent" = "easyclaw/$script:EASYCLAW_VERSION" }
        $release = Invoke-RestMethod -Uri $script:GITHUB_RELEASES -Headers $headers -TimeoutSec 10
        $latestVersion = $release.tag_name -replace '^v', ''
        $releaseNotes  = $release.body
    } catch {
        Write-Warn "Could not reach GitHub API. Check your internet connection."
        Write-Log "GitHub API error: $_" "ERROR"
        return
    }

    $installed = Get-InstalledVersion
    if (-not $installed) {
        Write-Warn "OpenClaw does not appear to be installed."
        return
    }

    Write-Info "Installed : v$installed"
    Write-Info "Latest    : v$latestVersion"

    # Compare versions (simple semver comparison)
    try {
        $instVer   = [Version]$installed
        $latestVer = [Version]$latestVersion
    } catch {
        $instVer   = $null
        $latestVer = $null
    }

    if ($instVer -and $latestVer -and $instVer -ge $latestVer) {
        Write-Success "You are already on the latest version."
        return
    }

    # Show release notes (first 20 lines)
    if ($releaseNotes) {
        Write-Host ""
        Write-Host "  What's new in v${latestVersion}:" -ForegroundColor Cyan
        $releaseNotes -split "`n" | Select-Object -First 20 | ForEach-Object {
            Write-Host "    $_"
        }
        Write-Host ""
    }

    if (-not (Confirm-Prompt "Proceed with update to v${latestVersion}?")) {
        Write-Info "Update cancelled."
        return
    }

    # Auto-backup first
    Write-Step "Creating pre-update backup"
    Invoke-Backup -Silent

    # Perform update
    Write-Step "Updating OpenClaw"
    try {
        if ($script:INSTALL_MODE -eq "docker") {
            Write-Info "Pulling latest Docker image..."
            $composeFile = Join-Path $script:EASYCLAW_DIR "docker-compose.yml"
            & docker compose -f $composeFile pull
            & docker compose -f $composeFile up -d
        } else {
            Write-Info "Running: npm update -g openclaw@latest"
            & npm update -g "openclaw@latest"
        }
    } catch {
        Write-Error2 "Update failed: $_"
        Write-Log "Update error: $_" "ERROR"
        return
    }

    # Run doctor post-update
    Write-Step "Running post-update health check"
    Invoke-Doctor

    $newVersion = Get-InstalledVersion
    Write-Success "Update complete. Now running v$newVersion"
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: BACKUP
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Backup {
    param([switch]$Silent)

    if (-not $Silent) { Write-Step "Backing up OpenClaw configuration" }

    Ensure-Dirs

    $timestamp  = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $archiveName = "backup-$timestamp.zip"
    $archivePath = Join-Path $script:BACKUP_DIR $archiveName

    # Collect items to back up
    $itemsToZip = @()

    $configFile = Get-ConfigPath
    if (Test-Path $configFile) { $itemsToZip += $configFile }

    $credDir = Join-Path $script:OPENCLAW_DIR "credentials"
    if (Test-Path $credDir) { $itemsToZip += $credDir }

    $workspaceDir = Join-Path $script:OPENCLAW_DIR "workspace"
    if (Test-Path $workspaceDir) {
        $wsSizeMB = Get-FolderSizeMB $workspaceDir
        $includeWs = $true
        if ($wsSizeMB -gt 100 -and -not $Silent) {
            Write-Warn "The workspace folder is ${wsSizeMB} MB."
            $includeWs = Confirm-Prompt "Include workspace in backup?"
        }
        if ($includeWs) { $itemsToZip += $workspaceDir }
    }

    if ($itemsToZip.Count -eq 0) {
        Write-Warn "Nothing found to back up in $script:OPENCLAW_DIR"
        return
    }

    # Create the archive via a temp staging directory
    $stagingDir = Join-Path $env:TEMP "easyclaw_backup_$timestamp"
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    foreach ($item in $itemsToZip) {
        $dest = Join-Path $stagingDir (Split-Path $item -Leaf)
        Copy-Item -Path $item -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
    }

    try {
        Compress-Archive -Path "$stagingDir\*" -DestinationPath $archivePath -CompressionLevel Optimal -Force
    } finally {
        Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $Silent) {
        $sizeMB = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
        Write-Success "Backup saved: $archivePath  (${sizeMB} MB)"
    }
    Write-Log "Backup created: $archivePath" "INFO"

    # Prune old backups — keep only MAX_BACKUPS most recent
    $allBackups = Get-ChildItem $script:BACKUP_DIR -Filter "*.zip" |
                  Sort-Object LastWriteTime -Descending
    if ($allBackups.Count -gt $script:MAX_BACKUPS) {
        $toRemove = $allBackups | Select-Object -Skip $script:MAX_BACKUPS
        foreach ($old in $toRemove) {
            Remove-Item $old.FullName -Force
            Write-Log "Pruned old backup: $($old.Name)" "INFO"
            if (-not $Silent) {
                Write-Info "Removed old backup: $($old.Name)"
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: RESTORE
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Restore {
    param([string]$BackupFile)

    Write-Step "Restoring from backup"

    Ensure-Dirs

    # If no file specified, list available backups and let user pick
    if (-not $BackupFile) {
        $backups = Get-ChildItem $script:BACKUP_DIR -Filter "*.zip" |
                   Sort-Object LastWriteTime -Descending
        if ($backups.Count -eq 0) {
            Write-Warn "No backups found in $script:BACKUP_DIR"
            Write-Info "Run 'easyclaw backup' first."
            return
        }

        Write-Host ""
        Write-Host "  Available backups:" -ForegroundColor Cyan
        $i = 1
        foreach ($b in $backups) {
            $sizeMB = [math]::Round($b.Length / 1MB, 2)
            Write-Host "  [$i] $($b.Name)  (${sizeMB} MB)  $($b.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
            $i++
        }
        Write-Host ""
        $choice = Read-Host "  Enter number to restore (or Q to cancel)"
        if ($choice -match '^[Qq]') { Write-Info "Restore cancelled."; return }

        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $backups.Count) {
            Write-Error2 "Invalid selection."
            return
        }
        $BackupFile = $backups[$idx].FullName
    }

    if (-not (Test-Path $BackupFile)) {
        Write-Error2 "File not found: $BackupFile"
        return
    }

    Write-Info "Restore file: $BackupFile"

    if (-not (Confirm-Prompt "This will OVERWRITE your current OpenClaw config. Continue?")) {
        Write-Info "Restore cancelled."
        return
    }

    # Stop gateway before restoring
    Write-Step "Stopping OpenClaw gateway"
    Invoke-Stop -Quiet

    # Expand archive into the openclaw dir
    Write-Info "Extracting archive..."
    try {
        if (-not (Test-Path $script:OPENCLAW_DIR)) {
            New-Item -ItemType Directory -Path $script:OPENCLAW_DIR -Force | Out-Null
        }
        Expand-Archive -Path $BackupFile -DestinationPath $script:OPENCLAW_DIR -Force
    } catch {
        Write-Error2 "Failed to extract archive: $_"
        Write-Log "Restore extract error: $_" "ERROR"
        return
    }

    Write-Success "Files restored to $script:OPENCLAW_DIR"

    # Restart gateway
    Write-Step "Restarting OpenClaw gateway"
    Invoke-Start -Quiet

    # Health check
    Start-Sleep -Seconds 3
    $running = Test-GatewayRunning
    if ($running) {
        Write-Success "Restore complete. Gateway is running."
    } else {
        Write-Warn "Restore complete, but gateway did not start automatically."
        Write-Info "Try: easyclaw start"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: CHANNELS
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Channels {
    param([string]$SubCommand, [string[]]$Rest)

    if (-not $SubCommand) { $SubCommand = "list" }

    switch ($SubCommand.ToLower()) {

        "list" {
            Write-Step "Configured channels"
            $cfg = Read-OpenClawConfig
            if (-not $cfg -or -not $cfg.channels) {
                Write-Warn "No channels configured."
                Write-Info "Add one with: easyclaw channels add <name>"
                return
            }
            $rows = @()
            foreach ($ch in $cfg.channels) {
                $status = $(if ($ch.enabled) { "enabled" } else { "disabled" })
                $rows += "$($ch.name.PadRight(20)) $($ch.type.PadRight(15)) $status"
            }
            Write-Box -Title "Channels" -Lines $rows
        }

        "add" {
            $chName = $(if ($Rest.Count -gt 0) { $Rest[0] } else {
                Read-Host "  Channel name"
            })
            Write-Step "Adding channel: $chName"
            try {
                & openclaw channel add $chName
                Write-Success "Channel '$chName' added."
            } catch {
                Write-Error2 "Failed to add channel: $_"
            }
        }

        "remove" {
            $chName = $(if ($Rest.Count -gt 0) { $Rest[0] } else {
                Read-Host "  Channel name to remove"
            })
            if (-not (Confirm-Prompt "Remove channel '$chName'?")) {
                Write-Info "Cancelled."
                return
            }
            Write-Step "Removing channel: $chName"
            try {
                & openclaw channel remove $chName
                Write-Success "Channel '$chName' removed."
            } catch {
                Write-Error2 "Failed to remove channel: $_"
            }
        }

        default {
            Write-Error2 "Unknown channels subcommand: $SubCommand"
            Write-Info "Valid: list | add <name> | remove <name>"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: LOGS
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Logs {
    param(
        [string]$Lines = "50"
    )

    # Parse -Lines from Args2 if passed as flag
    $linesInt = 50
    if ($Lines -match '^\d+$') { $linesInt = [int]$Lines }

    # Also scan Args2 for -Lines flag
    for ($i = 0; $i -lt $Args2.Count; $i++) {
        if ($Args2[$i] -in @("-Lines", "--lines", "-n") -and $i + 1 -lt $Args2.Count) {
            $linesInt = [int]$Args2[$i + 1]
            break
        }
    }

    Write-Step "OpenClaw logs (last $linesInt lines — Ctrl+C to stop)"
    Write-Host ""

    if ($script:INSTALL_MODE -eq "docker") {
        try {
            & docker compose -f (Join-Path $script:EASYCLAW_DIR "docker-compose.yml") `
                logs -f --tail $linesInt
        } catch {
            Write-Error2 "docker compose logs failed: $_"
        }
        return
    }

    # Native: find the openclaw log file
    $candidates = @(
        (Join-Path $script:OPENCLAW_DIR "logs" "openclaw.log"),
        (Join-Path $script:OPENCLAW_DIR "openclaw.log"),
        (Join-Path $env:TEMP "openclaw.log")
    )

    $logPath = $null
    foreach ($c in $candidates) {
        if (Test-Path $c) { $logPath = $c; break }
    }

    if (-not $logPath) {
        Write-Warn "No log file found. Tried:"
        $candidates | ForEach-Object { Write-Info "  $_" }
        return
    }

    Write-Info "Tailing: $logPath"
    Write-Host ""

    # Get-Content -Wait is the PowerShell equivalent of tail -f
    Get-Content -Path $logPath -Tail $linesInt -Wait
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: DOCTOR
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Doctor {
    Write-Step "Running diagnostics"

    $allGood = $true

    # 1. openclaw doctor (native tool)
    try {
        if ($script:INSTALL_MODE -eq "docker") {
            & docker exec openclaw openclaw doctor 2>&1 | ForEach-Object { Write-Info $_ }
        } else {
            & openclaw doctor 2>&1 | ForEach-Object { Write-Info $_ }
        }
    } catch {
        Write-Warn "Could not run 'openclaw doctor': $_"
        $allGood = $false
    }

    # 2. Node.js version check (native only)
    if ($script:INSTALL_MODE -eq "native") {
        try {
            $nodeVer = & node --version 2>$null
            if ($nodeVer -match 'v(\d+)') {
                $major = [int]$Matches[1]
                if ($major -ge 18) {
                    Write-Success "Node.js          : $nodeVer (OK)"
                } else {
                    Write-Warn "Node.js          : $nodeVer (recommend v18+)"
                    $allGood = $false
                }
            }
        } catch {
            Write-Warn "Node.js          : not found"
            $allGood = $false
        }
    }

    # 3. Disk space check (warn if < 500 MB free)
    try {
        $drive     = Split-Path -Qualifier $script:OPENCLAW_DIR
        $disk      = Get-PSDrive -Name ($drive.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($disk) {
            $freeMB = [math]::Round($disk.Free / 1MB, 0)
            if ($freeMB -gt 500) {
                Write-Success "Disk free        : ${freeMB} MB"
            } else {
                Write-Warn "Disk free        : ${freeMB} MB  (low!)"
                $allGood = $false
            }
        }
    } catch {}

    # 4. DNS resolution test
    $testHost = "api.openclaw.io"
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($testHost)
        if ($resolved.Count -gt 0) {
            Write-Success "DNS              : $testHost resolves OK"
        }
    } catch {
        Write-Warn "DNS              : cannot resolve $testHost"
        $allGood = $false
    }

    # 5. API connectivity test (simple TCP)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect("api.openclaw.io", 443, $null, $null)
        $waited = $conn.AsyncWaitHandle.WaitOne(3000, $false)
        $tcp.Close()
        if ($waited) {
            Write-Success "API endpoint     : reachable"
        } else {
            Write-Warn "API endpoint     : timeout (api.openclaw.io:443)"
            $allGood = $false
        }
    } catch {
        Write-Warn "API endpoint     : unreachable — $_"
        $allGood = $false
    }

    # 6. EasyClaw log location
    Write-Info "EasyClaw log     : $script:LOG_FILE"

    Write-Host ""
    if ($allGood) {
        Write-Host "  Overall        : " -NoNewline
        Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    } else {
        Write-Host "  Overall        : " -NoNewline
        Write-Host "SOME CHECKS FAILED (see warnings above)" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: RESTART
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Restart {
    Write-Step "Restarting OpenClaw gateway"

    try {
        if ($script:INSTALL_MODE -eq "docker") {
            $cf = Join-Path $script:EASYCLAW_DIR "docker-compose.yml"
            & docker compose -f $cf restart
        } else {
            & openclaw daemon restart
        }
    } catch {
        Write-Error2 "Restart command failed: $_"
        Write-Log "Restart error: $_" "ERROR"
        return
    }

    # Verify gateway comes back
    $attempts = 0
    $maxAttempts = 10
    Write-Info "Waiting for gateway..."
    while ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds 2
        if (Test-GatewayRunning) {
            Write-Success "Gateway is back online."
            return
        }
        $attempts++
    }
    Write-Warn "Gateway did not respond after $($maxAttempts * 2) seconds."
    Write-Info "Check logs: easyclaw logs"
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: STOP
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Stop {
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Step "Stopping OpenClaw gateway" }

    try {
        if ($script:INSTALL_MODE -eq "docker") {
            $cf = Join-Path $script:EASYCLAW_DIR "docker-compose.yml"
            & docker compose -f $cf stop
        } else {
            & openclaw daemon stop
        }
        if (-not $Quiet) { Write-Success "Gateway stopped." }
        Write-Log "Gateway stopped" "INFO"
    } catch {
        if (-not $Quiet) { Write-Error2 "Stop failed: $_" }
        Write-Log "Stop error: $_" "ERROR"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: START
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Start {
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Step "Starting OpenClaw gateway" }

    try {
        if ($script:INSTALL_MODE -eq "docker") {
            $cf = Join-Path $script:EASYCLAW_DIR "docker-compose.yml"
            & docker compose -f $cf up -d
        } else {
            & openclaw daemon start
        }
        if (-not $Quiet) { Write-Success "Gateway started." }
        Write-Log "Gateway started" "INFO"
    } catch {
        if (-not $Quiet) { Write-Error2 "Start failed: $_" }
        Write-Log "Start error: $_" "ERROR"
        return
    }

    # Brief wait then verify
    if (-not $Quiet) {
        Start-Sleep -Seconds 3
        if (Test-GatewayRunning) {
            Write-Success "Confirmed: gateway is running."
        } else {
            Write-Warn "Gateway may still be starting. Run 'easyclaw status' to check."
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: UNINSTALL
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Uninstall {
    Write-Host ""
    Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "  !!  You are about to UNINSTALL OpenClaw   !!" -ForegroundColor Red
    Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host ""

    # First confirmation
    if (-not (Confirm-Prompt "Are you sure you want to uninstall OpenClaw?")) {
        Write-Info "Uninstall cancelled. Good choice."
        return
    }

    # Second confirmation — type UNINSTALL
    Write-Host ""
    $confirm2 = Read-Host "  Type UNINSTALL (all caps) to confirm"
    if ($confirm2 -cne "UNINSTALL") {
        Write-Info "Uninstall cancelled."
        return
    }

    # Auto-backup
    Write-Step "Creating final backup before uninstall"
    Invoke-Backup

    $backupMsg = "Your backup is at: $script:BACKUP_DIR"

    # Stop service
    Write-Step "Stopping OpenClaw gateway"
    Invoke-Stop -Quiet

    # Remove the package
    Write-Step "Removing OpenClaw package"
    try {
        if ($script:INSTALL_MODE -eq "docker") {
            $cf = Join-Path $script:EASYCLAW_DIR "docker-compose.yml"
            & docker compose -f $cf down --volumes --remove-orphans
        } else {
            & npm uninstall -g openclaw
        }
        Write-Success "Package removed."
    } catch {
        Write-Warn "Package removal encountered an issue: $_"
    }

    # Remove .openclaw directory
    if (Test-Path $script:OPENCLAW_DIR) {
        if (Confirm-Prompt "Remove $script:OPENCLAW_DIR (all config and data)?") {
            Remove-Item $script:OPENCLAW_DIR -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed: $script:OPENCLAW_DIR"
        } else {
            Write-Info "Keeping $script:OPENCLAW_DIR"
        }
    }

    # Remove .easyclaw directory (but keep backups if user wants)
    if (Test-Path $script:EASYCLAW_DIR) {
        if (Confirm-Prompt "Remove $script:EASYCLAW_DIR (EasyClaw config — backups are inside!)?") {
            Remove-Item $script:EASYCLAW_DIR -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed: $script:EASYCLAW_DIR"
            $backupMsg = "Backup was inside $script:EASYCLAW_DIR (now removed)"
        } else {
            Write-Info "Keeping $script:EASYCLAW_DIR (your backups are safe)"
        }
    }

    # Remove from PATH — remove any entry containing "openclaw"
    try {
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $newPath = ($userPath -split ';' |
                    Where-Object { $_ -notmatch "openclaw" -and $_.Trim() -ne "" }) -join ';'
        if ($newPath -ne $userPath) {
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-Success "Removed openclaw from user PATH."
        }
    } catch {
        Write-Warn "Could not update PATH automatically. You may need to remove it manually."
    }

    Write-Host ""
    Write-Host "  Goodbye! OpenClaw has been uninstalled." -ForegroundColor Cyan
    Write-Host "  $backupMsg" -ForegroundColor Yellow
    Write-Host "  We hope to see you again." -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Uninstall completed" "INFO"
}

# ─────────────────────────────────────────────────────────────────────────────
#  COMMAND: HELP
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-Help {
    Write-Host ""
    Write-Host "  EasyClaw v$script:EASYCLAW_VERSION — OpenClaw manager for Windows" -ForegroundColor Cyan
    Write-Host "  Install mode: $script:INSTALL_MODE" -ForegroundColor DarkGray
    Write-Host ""

    $cmds = @(
        @{ Cmd = "status";    Desc = "Show gateway status, version, channels, disk usage" },
        @{ Cmd = "update";    Desc = "Check for updates and upgrade OpenClaw" },
        @{ Cmd = "backup";    Desc = "Backup config, credentials, and workspace" },
        @{ Cmd = "restore";   Desc = "Restore from a backup file (interactive picker)" },
        @{ Cmd = "channels";  Desc = "Manage channels: list | add <name> | remove <name>" },
        @{ Cmd = "logs";      Desc = "Stream live logs (-Lines N to set history)" },
        @{ Cmd = "doctor";    Desc = "Run diagnostics: Node, disk, DNS, API checks" },
        @{ Cmd = "restart";   Desc = "Restart the OpenClaw gateway" },
        @{ Cmd = "start";     Desc = "Start the OpenClaw gateway" },
        @{ Cmd = "stop";      Desc = "Stop the OpenClaw gateway" },
        @{ Cmd = "uninstall"; Desc = "Remove OpenClaw and all data (with backup)" },
        @{ Cmd = "version";   Desc = "Show EasyClaw version" },
        @{ Cmd = "help";      Desc = "Show this help message" }
    )

    # Table header
    $col1 = 12; $col2 = 55
    $hr = [string]::new('-', ($col1 + $col2 + 5))
    Write-Host "  $("Command".PadRight($col1))  Description" -ForegroundColor White
    Write-Host "  $hr" -ForegroundColor DarkGray

    foreach ($c in $cmds) {
        Write-Host "  " -NoNewline
        Write-Host $c.Cmd.PadRight($col1) -ForegroundColor Green -NoNewline
        Write-Host "  $($c.Desc)"
    }

    Write-Host ""
    Write-Host "  Usage: easyclaw <command> [options]" -ForegroundColor DarkGray
    Write-Host "  Logs:  $script:LOG_FILE" -ForegroundColor DarkGray
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  DEFAULT VIEW  (no command given)
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-DefaultView {
    $unknownCmd = $Command -and $Command -notin @("")
    if ($unknownCmd) {
        Write-Error2 "Unknown command: '$Command'"
        Write-Host ""
    }

    # Quick inline status
    Write-Host ""
    Write-Host "  EasyClaw v$script:EASYCLAW_VERSION" -ForegroundColor Cyan
    Write-Host "  OpenClaw manager for Windows" -ForegroundColor DarkGray
    Write-Host ""

    $running = Test-GatewayRunning
    $version = Get-InstalledVersion
    $modeLabel = "mode: $script:INSTALL_MODE"

    if ($version) {
        Write-Host "  OpenClaw v$version  |  " -NoNewline
        if ($running) {
            Write-Host "gateway: " -NoNewline; Write-Host "running" -ForegroundColor Green -NoNewline
        } else {
            Write-Host "gateway: " -NoNewline; Write-Host "stopped" -ForegroundColor Red -NoNewline
        }
        Write-Host "  |  $modeLabel"
    } else {
        Write-Host "  OpenClaw: not detected  |  $modeLabel"
    }

    Write-Host ""
    Write-Host "  Run 'easyclaw help' for available commands." -ForegroundColor DarkGray
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  ERROR TRAP
# ─────────────────────────────────────────────────────────────────────────────

trap {
    $errMsg = $_.Exception.Message
    Write-Host ""
    Write-Host "  [XX] Unexpected error: $errMsg" -ForegroundColor Red
    Write-Host "  Check the log for details: $script:LOG_FILE" -ForegroundColor DarkGray
    Write-Host ""
    Write-Log "Unhandled exception: $errMsg  |  ScriptStackTrace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN DISPATCH
# ─────────────────────────────────────────────────────────────────────────────

# Ensure essential directories exist on every run
Ensure-Dirs

switch ($Command) {
    "status"    { Invoke-Status }
    "update"    { Invoke-Update }
    "backup"    { Invoke-Backup }
    "restore"   { Invoke-Restore -BackupFile ($Args2 | Select-Object -First 1) }
    "channels"  {
        $sub  = $Args2 | Select-Object -First 1
        $rest = $(if ($Args2.Count -gt 1) { $Args2[1..($Args2.Count-1)] } else { @() })
        Invoke-Channels -SubCommand $sub -Rest $rest
    }
    "logs"      {
        # Support: easyclaw logs 100  OR  easyclaw logs -Lines 100
        $linesArg = "50"
        if ($Args2.Count -gt 0) {
            if ($Args2[0] -match '^\d+$') { $linesArg = $Args2[0] }
            elseif ($Args2[0] -in @("-Lines","--lines","-n") -and $Args2.Count -gt 1) {
                $linesArg = $Args2[1]
            }
        }
        Invoke-Logs -Lines $linesArg
    }
    "doctor"    { Invoke-Doctor }
    "restart"   { Invoke-Restart }
    "stop"      { Invoke-Stop }
    "start"     { Invoke-Start }
    "uninstall" { Invoke-Uninstall }
    "help"      { Invoke-Help }
    "--help"    { Invoke-Help }
    "-h"        { Invoke-Help }
    "version"   { Write-Host "easyclaw v$script:EASYCLAW_VERSION" }
    "--version" { Write-Host "easyclaw v$script:EASYCLAW_VERSION" }
    default     { Invoke-DefaultView }
}
