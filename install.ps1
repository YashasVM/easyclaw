#Requires -Version 5.1
<#
.SYNOPSIS
    EasyClaw — the friendliest way to install OpenClaw on Windows
.DESCRIPTION
    One-command installer for OpenClaw AI assistant.
    Handles Node.js, configuration, channels, and service setup.
    Supports native Windows (npm), Docker Desktop, and WSL2.
.EXAMPLE
    # Run from PowerShell:
    iwr -useb https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.ps1 | iex

    # Or with options:
    .\install.ps1 -Provider anthropic -Mode native
.LINK
    https://github.com/YashasVM/easyclaw
#>

[CmdletBinding()]
param(
    [string]$Provider,
    [string]$ApiKey,
    [string]$Mode,
    [string]$AssistantName = "Claw",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Speed up Invoke-WebRequest

# Enable TLS 1.2 for older Windows / PowerShell 5.1 systems
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================
# VERSION & GLOBALS
# ==============================================================================
$script:EASYCLAW_VERSION    = "1.0.0"
$script:OPENCLAW_MIN_NODE   = 22
$script:OPENCLAW_REC_NODE   = 24
$script:OPENCLAW_PORT       = 18789
$script:OPENCLAW_CONFIG_DIR = Join-Path $env:USERPROFILE ".openclaw"
$script:INSTALL_LOG         = Join-Path $env:TEMP "easyclaw-install.log"
$script:INSTALL_MODE        = ""          # native | docker | wsl2
$script:PROVIDER            = $Provider   # anthropic | openai | google | openrouter
$script:API_KEY             = $ApiKey
$script:MODEL               = ""
$script:ASSISTANT_NAME      = $AssistantName
$script:CHANNELS            = @()

# Channel tokens (populated during config step)
$script:TELEGRAM_TOKEN      = ""
$script:DISCORD_TOKEN       = ""
$script:SLACK_BOT_TOKEN     = ""
$script:SLACK_APP_TOKEN     = ""

# System detection results (populated in Step 1)
$script:WIN_VERSION         = ""
$script:WIN_BUILD           = 0
$script:IS_ADMIN            = $false
$script:PS_VERSION          = $PSVersionTable.PSVersion.Major
$script:NODE_VERSION        = "none"
$script:NODE_MAJOR          = 0
$script:NODE_OK             = $false
$script:DOCKER_INSTALLED    = $false
$script:DOCKER_RUNNING      = $false
$script:WSL2_AVAILABLE      = $false
$script:WINGET_AVAILABLE    = $false
$script:CHOCO_AVAILABLE     = $false
$script:SCOOP_AVAILABLE     = $false
$script:RAM_GB              = 0
$script:DISK_FREE_GB        = 0
$script:OPENCLAW_INSTALLED  = $false
$script:OPENCLAW_VERSION_INSTALLED = "none"

# Start logging — append everything to the log file
$null = New-Item -Path $script:INSTALL_LOG -ItemType File -Force 2>$null
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] EasyClaw $script:EASYCLAW_VERSION starting" |
    Out-File -Append -FilePath $script:INSTALL_LOG

# ==============================================================================
# COLOR / UI FUNCTIONS
# ==============================================================================

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO]  " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
    "INFO: $Message" | Out-File -Append -FilePath $script:INSTALL_LOG
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK]    " -ForegroundColor Green -NoNewline
    Write-Host $Message
    "OK: $Message" | Out-File -Append -FilePath $script:INSTALL_LOG
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!]     " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
    "WARN: $Message" | Out-File -Append -FilePath $script:INSTALL_LOG
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "[X]     " -ForegroundColor Red -NoNewline
    Write-Host $Message
    "ERROR: $Message" | Out-File -Append -FilePath $script:INSTALL_LOG
}

function Write-Step {
    param(
        [int]$Number,
        [int]$Total,
        [string]$Message
    )
    Write-Host ""
    Write-Host "[Step $Number/$Total] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message -ForegroundColor White
    Write-Host ("─" * 60) -ForegroundColor DarkGray
    "STEP $Number/$Total : $Message" | Out-File -Append -FilePath $script:INSTALL_LOG
}

function Read-UserInput {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )
    if ($Default -ne "") {
        Write-Host "  ? " -ForegroundColor Cyan -NoNewline
        Write-Host "$Prompt " -NoNewline
        Write-Host "[$Default]" -ForegroundColor DarkGray -NoNewline
        Write-Host ": " -NoNewline
    } else {
        Write-Host "  ? " -ForegroundColor Cyan -NoNewline
        Write-Host "${Prompt}: " -NoNewline
    }
    $response = Read-Host
    if ([string]::IsNullOrWhiteSpace($response)) { return $Default }
    return $response
}

function Read-SecretInput {
    param([string]$Prompt)
    Write-Host "  ? " -ForegroundColor Cyan -NoNewline
    Write-Host "$Prompt " -NoNewline
    # Use Read-Host with -AsSecureString for masking, then convert back
    $secure = Read-Host -AsSecureString
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 1
    )
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor White
    for ($i = 0; $i -lt $Options.Length; $i++) {
        Write-Host "  " -NoNewline
        Write-Host "$($i+1)" -ForegroundColor Cyan -NoNewline
        Write-Host ") $($Options[$i])"
    }
    while ($true) {
        Write-Host "  -> Enter number" -ForegroundColor Cyan -NoNewline
        Write-Host " [$Default]: " -ForegroundColor DarkGray -NoNewline
        $input = Read-Host
        if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
        if ($input -match '^\d+$') {
            $n = [int]$input
            if ($n -ge 1 -and $n -le $Options.Length) { return $n }
        }
        Write-Warn "Please enter a number between 1 and $($Options.Length)"
    }
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    Write-Host "  ? " -ForegroundColor Cyan -NoNewline
    Write-Host "$Prompt " -NoNewline
    Write-Host $hint -ForegroundColor DarkGray -NoNewline
    Write-Host ": " -NoNewline
    $response = Read-Host
    if ([string]::IsNullOrWhiteSpace($response)) { return $Default }
    return ($response -match '^[Yy]')
}

function Write-Box {
    param([string[]]$Lines, [int]$Width = 54)
    $top    = [char]0x2554 + ([char]0x2550 * $Width) + [char]0x2557
    $bottom = [char]0x255A + ([char]0x2550 * $Width) + [char]0x255D
    $div    = [char]0x2560 + ([char]0x2550 * $Width) + [char]0x2563
    $side   = [char]0x2551

    Write-Host $top -ForegroundColor Cyan
    foreach ($line in $Lines) {
        if ($line -eq "---") {
            Write-Host $div -ForegroundColor Cyan
        } else {
            # Strip any ANSI-like markup we might have embedded
            $clean  = $line -replace '\[.+?\]', ''
            $padLen = $Width - $clean.Length
            if ($padLen -lt 0) { $padLen = 0 }
            $pad = " " * $padLen
            Write-Host "$side" -ForegroundColor Cyan -NoNewline
            Write-Host "$line$pad" -NoNewline
            Write-Host "$side" -ForegroundColor Cyan
        }
    }
    Write-Host $bottom -ForegroundColor Cyan
}

function Show-Spinner {
    param(
        [string]$Message,
        [scriptblock]$ScriptBlock
    )
    $frames  = @('|', '/', '-', '\')
    $job     = Start-Job -ScriptBlock $ScriptBlock
    $i       = 0
    while ($job.State -eq 'Running') {
        $frame = $frames[$i % $frames.Length]
        Write-Host "`r  $frame  $Message   " -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 100
        $i++
    }
    Write-Host "`r  " -NoNewline
    Write-Host "OK" -ForegroundColor Green -NoNewline
    Write-Host "  $Message                    "
    $result = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force
    return $result
}

function Invoke-Quietly {
    <#
    .SYNOPSIS
        Runs a command, appending all output to the install log.
        Returns $true on success, $false on failure.
    #>
    param(
        [string]$Message,
        [scriptblock]$ScriptBlock
    )
    Write-Host "  ... $Message" -ForegroundColor DarkGray
    try {
        $output = & $ScriptBlock 2>&1
        $output | Out-File -Append -FilePath $script:INSTALL_LOG
        return $true
    } catch {
        $_.Exception.Message | Out-File -Append -FilePath $script:INSTALL_LOG
        return $false
    }
}

function Invoke-Command-Logged {
    <#
    .SYNOPSIS
        Runs an external command string, logs output, throws on failure.
    #>
    param([string]$Message, [string]$Command, [string[]]$Arguments)
    Write-Host "  ... $Message" -ForegroundColor DarkGray
    "[CMD] $Command $($Arguments -join ' ')" | Out-File -Append -FilePath $script:INSTALL_LOG
    try {
        $proc = Start-Process -FilePath $Command -ArgumentList $Arguments `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput "$env:TEMP\ec_stdout.tmp" `
            -RedirectStandardError  "$env:TEMP\ec_stderr.tmp"
        Get-Content "$env:TEMP\ec_stdout.tmp" -ErrorAction SilentlyContinue |
            Out-File -Append -FilePath $script:INSTALL_LOG
        Get-Content "$env:TEMP\ec_stderr.tmp" -ErrorAction SilentlyContinue |
            Out-File -Append -FilePath $script:INSTALL_LOG
        if ($proc.ExitCode -ne 0) {
            throw "Command exited with code $($proc.ExitCode): $Command $($Arguments -join ' ')"
        }
    } catch {
        throw $_
    }
}

function Refresh-Path {
    # Reload the PATH from the registry so newly-installed tools are visible
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH    = "$machinePath;$userPath"
}

# ==============================================================================
# ASCII ART BANNER
# ==============================================================================
function Show-Banner {
    Write-Host ""
    Write-Host "  ___                  ___ _" -ForegroundColor Cyan
    Write-Host " | __|__ _ ____  _  __|  _| |__ ___ __ __" -ForegroundColor Cyan
    Write-Host " | _|/ _`` (_-< || |/ _|| |/ _/ _ \  V  V /" -ForegroundColor Cyan
    Write-Host " |___\__,_/__/\_,_|\__||_|\__\___/\_/\_/ " -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The friendliest way to install OpenClaw on Windows" -ForegroundColor DarkGray
    Write-Host "  v$script:EASYCLAW_VERSION" -ForegroundColor DarkGray
    Write-Host "  Install log: $script:INSTALL_LOG" -ForegroundColor DarkGray
    Write-Host ""
}

# ==============================================================================
# STEP 1: ENVIRONMENT DETECTION
# ==============================================================================
function Step1-DetectEnvironment {
    Write-Step -Number 1 -Total 8 -Message "Checking your system"

    # ---- Windows Version ----
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($osInfo) {
            $script:WIN_VERSION = $osInfo.Caption
            $script:WIN_BUILD   = [int]($osInfo.BuildNumber)
        }
    } catch {
        $script:WIN_VERSION = "Windows (version unknown)"
    }

    # ---- Administrator check ----
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $script:IS_ADMIN  = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # ---- PowerShell version ----
    $script:PS_VERSION = $PSVersionTable.PSVersion.Major

    # ---- WSL2 ----
    $wslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wslExe) {
        $wslStatus = wsl.exe --status 2>$null
        $script:WSL2_AVAILABLE = ($LASTEXITCODE -eq 0) -or ($null -ne $wslStatus)
    }

    # ---- Node.js ----
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $rawVer = (node --version 2>$null).TrimStart('v').Trim()
        if ($rawVer -match '^(\d+)') {
            $script:NODE_VERSION = $rawVer
            $script:NODE_MAJOR   = [int]$Matches[1]
            $script:NODE_OK      = ($script:NODE_MAJOR -ge $script:OPENCLAW_MIN_NODE)
        }
    }

    # ---- Docker ----
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCmd) {
        $script:DOCKER_INSTALLED = $true
        $dockerInfo = docker info 2>$null
        $script:DOCKER_RUNNING = ($LASTEXITCODE -eq 0)
    }

    # ---- Package managers ----
    $script:WINGET_AVAILABLE = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $script:CHOCO_AVAILABLE  = $null -ne (Get-Command choco  -ErrorAction SilentlyContinue)
    $script:SCOOP_AVAILABLE  = $null -ne (Get-Command scoop  -ErrorAction SilentlyContinue)

    # ---- RAM ----
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs) { $script:RAM_GB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }
    } catch { }

    # ---- Disk free (C:\) ----
    try {
        $disk = Get-PSDrive C -ErrorAction SilentlyContinue
        if ($disk) { $script:DISK_FREE_GB = [math]::Round($disk.Free / 1GB, 1) }
    } catch { }

    # ---- Existing OpenClaw ----
    $oclawCmd = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($oclawCmd) {
        $script:OPENCLAW_INSTALLED = $true
        $script:OPENCLAW_VERSION_INSTALLED = (openclaw --version 2>$null | Select-Object -First 1) -replace "`n",""
    }

    # ---- Print summary box ----
    Write-Host ""
    $boxLines = @(
        "  System Summary",
        "---",
        "  OS:           $script:WIN_VERSION",
        "  Build:        $script:WIN_BUILD",
        "  PowerShell:   $($PSVersionTable.PSVersion)",
        "  RAM:          $script:RAM_GB GB",
        "  Disk free:    $script:DISK_FREE_GB GB  (C:\)",
        "---"
    )

    # Node
    $nodeLabel = if ($script:NODE_OK) { "Node.js:      $script:NODE_VERSION  [OK]" }
                 elseif ($script:NODE_VERSION -ne "none") { "Node.js:      $script:NODE_VERSION  [need >= $script:OPENCLAW_MIN_NODE]" }
                 else { "Node.js:      not found" }
    $boxLines += "  $nodeLabel"

    # Docker
    $dockerLabel = if ($script:DOCKER_RUNNING) { "Docker:       running  [OK]" }
                   elseif ($script:DOCKER_INSTALLED) { "Docker:       installed (not running)" }
                   else { "Docker:       not installed" }
    $boxLines += "  $dockerLabel"

    # WSL2
    $wsl2Label = if ($script:WSL2_AVAILABLE) { "WSL2:         available" } else { "WSL2:         not detected" }
    $boxLines += "  $wsl2Label"

    # Package managers
    $pkgMgrs = @()
    if ($script:WINGET_AVAILABLE) { $pkgMgrs += "winget" }
    if ($script:CHOCO_AVAILABLE)  { $pkgMgrs += "chocolatey" }
    if ($script:SCOOP_AVAILABLE)  { $pkgMgrs += "scoop" }
    $pkgLabel = if ($pkgMgrs.Count -gt 0) { $pkgMgrs -join ", " } else { "none found" }
    $boxLines += "  Package mgrs: $pkgLabel"

    # OpenClaw
    $oclawLabel = if ($script:OPENCLAW_INSTALLED) { "OpenClaw:     already installed ($script:OPENCLAW_VERSION_INSTALLED)" }
                  else { "OpenClaw:     not installed" }
    $boxLines += "  $oclawLabel"

    Write-Box -Lines $boxLines -Width 54
    Write-Host ""

    # ---- Warnings ----
    if (-not $script:IS_ADMIN) {
        Write-Warn "Not running as Administrator. Some installs may need elevation."
        Write-Warn "If anything fails, try: Start-Process powershell -Verb RunAs"
    }
    if ($script:RAM_GB -lt 2 -and $script:RAM_GB -gt 0) {
        Write-Warn "Low RAM ($script:RAM_GB GB). OpenClaw recommends at least 2 GB."
    }
    if ($script:DISK_FREE_GB -lt 5 -and $script:DISK_FREE_GB -gt 0) {
        Write-Warn "Low disk space ($script:DISK_FREE_GB GB free). OpenClaw recommends at least 5 GB."
    }
    if ($script:WIN_BUILD -lt 17763) {
        Write-Warn "Windows build $script:WIN_BUILD is older than Windows 10 1809. Some features may not work."
    }

    # ---- Reinstall check ----
    if ($script:OPENCLAW_INSTALLED) {
        Write-Warn "OpenClaw is already installed ($script:OPENCLAW_VERSION_INSTALLED)."
        $reinstall = Read-YesNo -Prompt "Do you want to upgrade/reinstall?" -Default $true
        if (-not $reinstall) {
            Write-Success "Nothing to do. Goodbye!"
            exit 0
        }
        Write-Info "Proceeding with upgrade/reinstall."
    }
}

# ==============================================================================
# STEP 2: CHOOSE DEPLOYMENT MODE
# ==============================================================================
function Step2-ChooseMode {
    Write-Step -Number 2 -Total 8 -Message "Choose your deployment mode"

    # Honor -Mode parameter if given
    if ($script:INSTALL_MODE -ne "") {
        Write-Success "Mode pre-selected: $script:INSTALL_MODE"
        return
    }
    if ($Mode -ne "") {
        $script:INSTALL_MODE = $Mode.ToLower()
        Write-Success "Mode pre-selected: $script:INSTALL_MODE"
        return
    }

    Write-Host ""
    Write-Host "  EasyClaw detected: $script:WIN_VERSION" -ForegroundColor DarkGray
    Write-Host ""

    $options = @(
        "Quick Install (Recommended) — Native npm install. Best for most users.",
        "Docker Desktop              — Containerized. Needs Docker Desktop installed.",
        "WSL2 Install                — Runs the Linux installer inside WSL2. Needs WSL2."
    )

    # Mark recommended
    $options[0] += "  <-- Recommended"
    if ($script:DOCKER_RUNNING)  { $options[1] += "  <-- Docker is ready!" }
    if ($script:WSL2_AVAILABLE)  { $options[2] += "  <-- WSL2 detected!" }
    if (-not $script:WSL2_AVAILABLE) { $options[2] += "  (WSL2 not detected)" }

    $choice = Read-Choice -Prompt "How do you want to run OpenClaw?" -Options $options -Default 1

    switch ($choice) {
        1 { $script:INSTALL_MODE = "native"; Write-Success "Mode: Quick Install (native npm)" }
        2 { $script:INSTALL_MODE = "docker"; Write-Success "Mode: Docker Desktop" }
        3 { $script:INSTALL_MODE = "wsl2";   Write-Success "Mode: WSL2" }
    }
}

# ==============================================================================
# STEP 3: INSTALL DEPENDENCIES
# ==============================================================================
function Step3-InstallDependencies {
    Write-Step -Number 3 -Total 8 -Message "Installing dependencies"

    switch ($script:INSTALL_MODE) {
        "native" { Install-Deps-Native }
        "docker" { Install-Deps-Docker }
        "wsl2"   { Install-Deps-WSL2   }
    }
}

function Install-NodeJS {
    <#
    .SYNOPSIS
        Install Node.js LTS using the best available method:
        winget -> direct MSI download -> chocolatey
    #>

    Write-Info "Node.js $script:OPENCLAW_REC_NODE or newer is required. Installing..."

    $installed = $false

    # --- Try winget first (preferred, comes with Win10 1809+) ---
    if ($script:WINGET_AVAILABLE) {
        Write-Info "Trying winget..."
        try {
            $ok = Invoke-Quietly -Message "Installing Node.js LTS via winget" -ScriptBlock {
                winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements 2>&1
            }
            Refresh-Path
            $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
            if ($nodeCheck) {
                $ver = (node --version 2>$null).TrimStart('v').Trim()
                $maj = [int]($ver -split '\.')[0]
                if ($maj -ge $script:OPENCLAW_MIN_NODE) {
                    Write-Success "Node.js $ver installed via winget"
                    $installed = $true
                }
            }
        } catch {
            Write-Warn "winget install failed: $_"
        }
    }

    # --- Fallback: direct MSI download from nodejs.org ---
    if (-not $installed) {
        Write-Info "Falling back to direct download from nodejs.org..."
        try {
            $nodeUrl = "https://nodejs.org/dist/latest-v$($script:OPENCLAW_REC_NODE).x/node-v$($script:OPENCLAW_REC_NODE).0.0-x64.msi"
            # Fetch the real latest version number first
            $indexPage = Invoke-WebRequest -Uri "https://nodejs.org/dist/latest-v$($script:OPENCLAW_REC_NODE).x/" -UseBasicParsing -ErrorAction SilentlyContinue
            if ($indexPage) {
                $match = [regex]::Match($indexPage.Content, "node-v($($script:OPENCLAW_REC_NODE)\.\d+\.\d+)-x64\.msi")
                if ($match.Success) {
                    $nodeUrl = "https://nodejs.org/dist/latest-v$($script:OPENCLAW_REC_NODE).x/node-v$($match.Groups[1].Value)-x64.msi"
                }
            }
            $msiPath = Join-Path $env:TEMP "node-lts.msi"
            Write-Info "Downloading Node.js MSI from nodejs.org..."
            Invoke-WebRequest -Uri $nodeUrl -OutFile $msiPath -UseBasicParsing
            Write-Info "Running Node.js installer (silent)..."
            $proc = Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -PassThru
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Refresh-Path
                $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
                if ($nodeCheck) {
                    Write-Success "Node.js installed via MSI download"
                    $installed = $true
                }
            } else {
                Write-Warn "MSI installer exited with code $($proc.ExitCode)"
            }
            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warn "Direct download failed: $_"
        }
    }

    # --- Fallback: Chocolatey ---
    if (-not $installed -and $script:CHOCO_AVAILABLE) {
        Write-Info "Trying Chocolatey..."
        try {
            Invoke-Quietly -Message "Installing nodejs-lts via chocolatey" -ScriptBlock {
                choco install nodejs-lts -y --no-progress 2>&1
            }
            Refresh-Path
            $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
            if ($nodeCheck) {
                Write-Success "Node.js installed via Chocolatey"
                $installed = $true
            }
        } catch {
            Write-Warn "Chocolatey install failed: $_"
        }
    }

    if (-not $installed) {
        Write-Error2 "Could not install Node.js automatically."
        Write-Host ""
        Write-Host "  Please install Node.js manually:" -ForegroundColor Yellow
        Write-Host "    https://nodejs.org/en/download" -ForegroundColor Cyan
        Write-Host "  Choose the LTS version for Windows x64 (.msi installer)." -ForegroundColor Yellow
        Write-Host "  After installing, close and reopen PowerShell, then run this script again." -ForegroundColor Yellow
        Write-Host ""
        throw "Node.js installation required — please install manually and re-run."
    }

    # Update detection variables
    $rawVer = (node --version 2>$null).TrimStart('v').Trim()
    $script:NODE_VERSION = $rawVer
    $script:NODE_MAJOR   = [int]($rawVer -split '\.')[0]
    $script:NODE_OK      = ($script:NODE_MAJOR -ge $script:OPENCLAW_MIN_NODE)
}

function Install-Git {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) { Write-Success "git already installed"; return }

    Write-Info "Installing git..."
    $gitInstalled = $false

    if ($script:WINGET_AVAILABLE) {
        try {
            Invoke-Quietly -Message "Installing git via winget" -ScriptBlock {
                winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements 2>&1
            }
            Refresh-Path
            if (Get-Command git -ErrorAction SilentlyContinue) { $gitInstalled = $true }
        } catch { }
    }

    if (-not $gitInstalled -and $script:CHOCO_AVAILABLE) {
        try {
            Invoke-Quietly -Message "Installing git via chocolatey" -ScriptBlock {
                choco install git -y --no-progress 2>&1
            }
            Refresh-Path
            if (Get-Command git -ErrorAction SilentlyContinue) { $gitInstalled = $true }
        } catch { }
    }

    if ($gitInstalled) {
        Write-Success "git installed"
    } else {
        Write-Warn "Could not install git automatically. Some features may be limited."
        Write-Warn "Manual install: https://git-scm.com/download/win"
    }
}

function Install-Deps-Native {
    # Node.js
    if (-not $script:NODE_OK) {
        if ($script:NODE_VERSION -ne "none") {
            Write-Warn "Node.js $script:NODE_VERSION found, but >= $script:OPENCLAW_MIN_NODE is required."
        }
        Install-NodeJS
    } else {
        Write-Success "Node.js $script:NODE_VERSION is ready (>= $script:OPENCLAW_MIN_NODE)"
    }

    # npm sanity check
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        # npm ships with Node, but PATH might not be refreshed
        Refresh-Path
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npmCmd) {
            throw "npm not found even after installing Node.js. Please restart PowerShell and try again."
        }
    }
    Write-Success "npm ready: $(npm --version 2>$null)"

    # Git (optional but recommended)
    Install-Git
}

function Install-Deps-Docker {
    if ($script:DOCKER_RUNNING) {
        Write-Success "Docker Desktop is running and ready"
        return
    }

    if ($script:DOCKER_INSTALLED) {
        Write-Warn "Docker Desktop is installed but not running."
        Write-Host ""
        Write-Host "  Please start Docker Desktop and then press Enter to continue..." -ForegroundColor Yellow
        $null = Read-Host
        # Re-check
        $result = docker info 2>$null
        $script:DOCKER_RUNNING = ($LASTEXITCODE -eq 0)
        if (-not $script:DOCKER_RUNNING) {
            throw "Docker is still not running. Please ensure Docker Desktop is fully started before retrying."
        }
        Write-Success "Docker Desktop is now running"
        return
    }

    # Docker not installed — guide user
    Write-Host ""
    Write-Box -Lines @(
        "  Docker Desktop Not Installed",
        "---",
        "  Docker Desktop cannot be auto-installed on Windows",
        "  because it requires Hyper-V setup and a system restart.",
        "  ",
        "  Please:",
        "    1. Visit:  https://www.docker.com/products/docker-desktop",
        "    2. Download and run the installer",
        "    3. Restart Windows when prompted",
        "    4. Start Docker Desktop",
        "    5. Run this installer again"
    ) -Width 54
    Write-Host ""

    $switchMode = Read-YesNo -Prompt "Switch to Quick Install (native npm) instead?" -Default $true
    if ($switchMode) {
        $script:INSTALL_MODE = "native"
        Write-Info "Switched to native mode."
        Install-Deps-Native
    } else {
        throw "Docker Desktop is required for Docker mode. Please install it and re-run."
    }
}

function Install-Deps-WSL2 {
    if (-not $script:WSL2_AVAILABLE) {
        Write-Warn "WSL2 is not installed or not available on this system."
        Write-Host ""

        $installWSL = Read-YesNo -Prompt "Install WSL2 now? (requires Admin + system restart)" -Default $true
        if ($installWSL) {
            if (-not $script:IS_ADMIN) {
                Write-Error2 "WSL2 installation requires Administrator privileges."
                Write-Info "Please re-run PowerShell as Administrator and try again."
                throw "Admin required to install WSL2."
            }
            Write-Info "Running: wsl --install"
            Write-Info "This will install WSL2 with Ubuntu. A restart will be required."
            Start-Process -FilePath "wsl.exe" -ArgumentList "--install" -Wait -NoNewWindow
            Write-Host ""
            Write-Host "  WSL2 installation initiated." -ForegroundColor Green
            Write-Host "  Please restart Windows and then run this installer again." -ForegroundColor Yellow
            Write-Host ""
            exit 0
        } else {
            Write-Info "Switching to Quick Install (native npm) instead."
            $script:INSTALL_MODE = "native"
            Install-Deps-Native
        }
        return
    }

    Write-Success "WSL2 is available. The Linux installer will run inside WSL2."
}

# ==============================================================================
# STEP 4: CONFIGURE OPENCLAW
# ==============================================================================
function Step4-Configure {
    Write-Step -Number 4 -Total 8 -Message "Configuring your AI assistant"
    Write-Host "  Just a few quick questions — press Enter to accept the defaults." -ForegroundColor DarkGray
    Write-Host ""

    # ---- 4.1 Assistant name ----
    Write-Host "  This is the name your assistant responds to." -ForegroundColor DarkGray
    $script:ASSISTANT_NAME = Read-UserInput -Prompt "What should we call your AI assistant?" -Default $script:ASSISTANT_NAME

    # ---- 4.2 AI Provider ----
    Write-Host ""
    Write-Host "  EasyClaw supports all major AI providers." -ForegroundColor DarkGray

    $providerOptions = @(
        "Anthropic (Claude)   — Recommended, best quality",
        "OpenAI (GPT)         — Popular, powerful",
        "Google (Gemini)      — Free tier available",
        "OpenRouter           — Access 100+ models with one key"
    )

    # Auto-select provider if passed via param
    $providerChoice = 0
    if ($script:PROVIDER -ne "") {
        switch ($script:PROVIDER.ToLower()) {
            "anthropic"  { $providerChoice = 1 }
            "openai"     { $providerChoice = 2 }
            "google"     { $providerChoice = 3 }
            "openrouter" { $providerChoice = 4 }
        }
    }

    if ($providerChoice -eq 0) {
        $providerChoice = Read-Choice -Prompt "Which AI provider do you want to use?" -Options $providerOptions -Default 1
    }

    $providerUrl = ""
    switch ($providerChoice) {
        1 {
            $script:PROVIDER = "anthropic"
            $script:MODEL    = "anthropic/claude-opus-4-5"
            $providerUrl     = "https://console.anthropic.com/settings/keys"
        }
        2 {
            $script:PROVIDER = "openai"
            $script:MODEL    = "openai/gpt-4o"
            $providerUrl     = "https://platform.openai.com/api-keys"
        }
        3 {
            $script:PROVIDER = "google"
            $script:MODEL    = "google/gemini-2.0-flash"
            $providerUrl     = "https://aistudio.google.com/app/apikey"
        }
        4 {
            $script:PROVIDER = "openrouter"
            $script:MODEL    = "openrouter/anthropic/claude-opus-4-5"
            $providerUrl     = "https://openrouter.ai/keys"
        }
    }
    Write-Success "Provider: $script:PROVIDER  (model: $script:MODEL)"

    # ---- 4.3 API Key ----
    Write-Host ""
    Write-Host "  Get your API key from: " -ForegroundColor DarkGray -NoNewline
    Write-Host $providerUrl -ForegroundColor Cyan

    if ($script:API_KEY -eq "") {
        $keyValid = $false
        while (-not $keyValid) {
            $script:API_KEY = Read-SecretInput -Prompt "Paste your API key (input is hidden):"
            if ($script:API_KEY.Length -lt 8) {
                Write-Warn "That key looks too short — are you sure it's correct?"
                $retry = Read-YesNo -Prompt "Try again?" -Default $true
                if (-not $retry) { $keyValid = $true } # accept short key
            } else {
                $keyValid = $true
            }
        }
    }
    Write-Success "API key received ($($script:API_KEY.Length) characters)"

    # ---- 4.4 Messaging channels ----
    Write-Host ""
    Write-Host "  You can always add more channels later with: easyclaw channels add" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Which messaging channels do you want to connect?" -ForegroundColor White
    Write-Host "  Enter numbers comma-separated, e.g: 2,3 — or press Enter for web only." -ForegroundColor DarkGray
    Write-Host ""

    $channelOptions = @(
        "None — use web dashboard only",
        "Telegram",
        "Discord",
        "WhatsApp",
        "Slack"
    )
    for ($i = 0; $i -lt $channelOptions.Length; $i++) {
        Write-Host "  " -NoNewline
        Write-Host "$($i+1)" -ForegroundColor Cyan -NoNewline
        Write-Host ") $($channelOptions[$i])"
    }
    Write-Host "  -> " -ForegroundColor Cyan -NoNewline
    Write-Host "Your choices [1]: " -ForegroundColor DarkGray -NoNewline
    $channelInput = Read-Host
    if ([string]::IsNullOrWhiteSpace($channelInput)) { $channelInput = "1" }

    $picks = $channelInput -split ',' | ForEach-Object { $_.Trim() }
    foreach ($pick in $picks) {
        switch ($pick) {
            "1" { }  # none/dashboard only
            "2" { $script:CHANNELS += "telegram" }
            "3" { $script:CHANNELS += "discord"  }
            "4" { $script:CHANNELS += "whatsapp" }
            "5" { $script:CHANNELS += "slack"    }
        }
    }

    if ($script:CHANNELS.Count -eq 0) {
        Write-Success "No channels selected — web dashboard only"
    } else {
        Write-Success "Channels selected: $($script:CHANNELS -join ', ')"
    }

    # ---- 4.5 Channel tokens ----
    Configure-ChannelTokens
}

function Configure-ChannelTokens {
    foreach ($ch in $script:CHANNELS) {
        switch ($ch) {
            "telegram" {
                Write-Host ""
                Write-Host "  Telegram Setup" -ForegroundColor Cyan
                Write-Host "  Create a bot at: https://t.me/BotFather — send /newbot and follow the steps." -ForegroundColor DarkGray
                Write-Host ""
                $script:TELEGRAM_TOKEN = Read-SecretInput -Prompt "Paste your Telegram Bot Token:"
                Write-Success "Telegram token received"
            }
            "discord" {
                Write-Host ""
                Write-Host "  Discord Setup" -ForegroundColor Cyan
                Write-Host "  Create a bot at: https://discord.com/developers/applications" -ForegroundColor DarkGray
                Write-Host "  -> New Application -> Bot -> Reset Token -> copy it here." -ForegroundColor DarkGray
                Write-Host ""
                $script:DISCORD_TOKEN = Read-SecretInput -Prompt "Paste your Discord Bot Token:"
                Write-Success "Discord token received"
            }
            "whatsapp" {
                Write-Host ""
                Write-Host "  WhatsApp Setup" -ForegroundColor Cyan
                Write-Host "  No token needed! After install, a QR code will appear — scan it with WhatsApp." -ForegroundColor DarkGray
                Write-Success "WhatsApp: will show QR code after install"
            }
            "slack" {
                Write-Host ""
                Write-Host "  Slack Setup" -ForegroundColor Cyan
                Write-Host "  Create a Slack app at: https://api.slack.com/apps" -ForegroundColor DarkGray
                Write-Host "  Bot Token  = xoxb-...  (OAuth & Permissions page)" -ForegroundColor DarkGray
                Write-Host "  App Token  = xapp-...  (Basic Information -> App-Level Tokens)" -ForegroundColor DarkGray
                Write-Host ""
                $script:SLACK_BOT_TOKEN = Read-SecretInput -Prompt "Paste your Slack Bot Token (xoxb-...):"
                $script:SLACK_APP_TOKEN = Read-SecretInput -Prompt "Paste your Slack App Token (xapp-...):"
                Write-Success "Slack tokens received"
            }
        }
    }
}

# ==============================================================================
# CONFIG FILE GENERATION
# ==============================================================================
function Build-ConfigObject {
    <#
    .SYNOPSIS
        Returns a hashtable representing openclaw.json
    #>
    $cfg = @{
        version       = "1.0"
        assistantName = $script:ASSISTANT_NAME
        provider      = $script:PROVIDER
        model         = $script:MODEL
        port          = $script:OPENCLAW_PORT
        channels      = @{}
    }

    foreach ($ch in $script:CHANNELS) {
        switch ($ch) {
            "telegram" { $cfg.channels["telegram"] = @{ token = $script:TELEGRAM_TOKEN } }
            "discord"  { $cfg.channels["discord"]  = @{ token = $script:DISCORD_TOKEN  } }
            "whatsapp" { $cfg.channels["whatsapp"] = @{} }
            "slack"    { $cfg.channels["slack"]    = @{ botToken = $script:SLACK_BOT_TOKEN; appToken = $script:SLACK_APP_TOKEN } }
        }
    }

    return $cfg
}

function Write-OpenClawConfig {
    $cfg    = Build-ConfigObject
    $json   = $cfg | ConvertTo-Json -Depth 10
    $cfgDir = $script:OPENCLAW_CONFIG_DIR

    if (-not (Test-Path $cfgDir)) {
        New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
    }

    $cfgFile = Join-Path $cfgDir "openclaw.json"
    Set-Content -Path $cfgFile -Value $json -Encoding UTF8
    Write-Success "Config written to $cfgFile"
}

function Write-EnvFile {
    param([string]$Path)
    $lines = @(
        "# EasyClaw / OpenClaw environment — generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "OPENCLAW_PROVIDER=$script:PROVIDER",
        "OPENCLAW_MODEL=$script:MODEL",
        "OPENCLAW_API_KEY=$script:API_KEY",
        "OPENCLAW_ASSISTANT_NAME=$script:ASSISTANT_NAME",
        "OPENCLAW_PORT=$script:OPENCLAW_PORT",
        "OPENCLAW_CONFIG_DIR=/root/.openclaw"
    )
    if ($script:TELEGRAM_TOKEN) { $lines += "TELEGRAM_BOT_TOKEN=$script:TELEGRAM_TOKEN" }
    if ($script:DISCORD_TOKEN)  { $lines += "DISCORD_BOT_TOKEN=$script:DISCORD_TOKEN"   }
    if ($script:SLACK_BOT_TOKEN){ $lines += "SLACK_BOT_TOKEN=$script:SLACK_BOT_TOKEN"   }
    if ($script:SLACK_APP_TOKEN){ $lines += "SLACK_APP_TOKEN=$script:SLACK_APP_TOKEN"    }

    $lines | Out-File -FilePath $Path -Encoding UTF8
    Write-Success ".env written to $Path"
}

function Write-DockerCompose {
    param([string]$Path)
    $yaml = @"
# Generated by EasyClaw $script:EASYCLAW_VERSION on $(Get-Date -Format 'yyyy-MM-dd')
version: "3.9"

services:
  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "$script:OPENCLAW_PORT`:$script:OPENCLAW_PORT"
    volumes:
      - openclaw_data:/root/.openclaw
    env_file:
      - .env
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$script:OPENCLAW_PORT/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  openclaw_data:
"@
    Set-Content -Path $Path -Value $yaml -Encoding UTF8
    Write-Success "docker-compose.yml written to $Path"
}

# ==============================================================================
# STEP 5: INSTALL OPENCLAW
# ==============================================================================
function Step5-InstallOpenClaw {
    Write-Step -Number 5 -Total 8 -Message "Installing OpenClaw"

    switch ($script:INSTALL_MODE) {
        "native" { Install-OpenClaw-Native }
        "docker" { Install-OpenClaw-Docker }
        "wsl2"   { Install-OpenClaw-WSL2   }
    }
}

function Install-OpenClaw-Native {
    Write-Info "Installing OpenClaw via npm..."

    # Re-check npm is available (path may have changed)
    Refresh-Path
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        throw "npm not found. Please restart PowerShell after Node.js install and try again."
    }

    try {
        Invoke-Quietly -Message "npm install -g openclaw@latest" -ScriptBlock {
            npm install -g openclaw@latest 2>&1
        }
    } catch {
        throw "npm install failed. Check the log: $script:INSTALL_LOG"
    }

    Refresh-Path
    $oclawCmd = Get-Command openclaw -ErrorAction SilentlyContinue
    if (-not $oclawCmd) {
        # npm global bin might not be in PATH yet
        $npmBin = (npm bin -g 2>$null).Trim()
        if ($npmBin -and (Test-Path $npmBin)) {
            $env:PATH = "$env:PATH;$npmBin"
            # Persist to user PATH
            $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath -notlike "*$npmBin*") {
                [System.Environment]::SetEnvironmentVariable("PATH", "$userPath;$npmBin", "User")
                Write-Info "Added npm global bin to user PATH: $npmBin"
            }
        }
        $oclawCmd = Get-Command openclaw -ErrorAction SilentlyContinue
    }

    if (-not $oclawCmd) {
        Write-Warn "openclaw command not immediately found — this is normal after a fresh install."
        Write-Warn "It will be available in new PowerShell windows after PATH updates."
    } else {
        $oclawVer = (openclaw --version 2>$null | Select-Object -First 1)
        Write-Success "openclaw installed: $oclawVer"
    }

    # Write config file
    Write-OpenClawConfig

    # Run onboard if openclaw is reachable
    if ($oclawCmd) {
        Write-Info "Running openclaw onboard..."
        try {
            $ok = Invoke-Quietly -Message "Running openclaw onboard --install-daemon" -ScriptBlock {
                openclaw onboard --install-daemon 2>&1
            }
            Write-Success "OpenClaw onboarding complete"
        } catch {
            Write-Warn "openclaw onboard had issues — you may need to run 'openclaw onboard' manually."
        }
    }
}

function Install-OpenClaw-Docker {
    $deployDir = Join-Path $env:USERPROFILE "easyclaw"
    Write-Info "Deploying OpenClaw to $deployDir..."

    # Create deploy directory
    if (-not (Test-Path $deployDir)) {
        New-Item -Path $deployDir -ItemType Directory -Force | Out-Null
    }

    # Write env file and docker-compose.yml
    Write-EnvFile       -Path (Join-Path $deployDir ".env")
    Write-DockerCompose -Path (Join-Path $deployDir "docker-compose.yml")

    # Pull and start containers
    Write-Info "Pulling OpenClaw Docker image (may take a minute)..."
    try {
        Invoke-Quietly -Message "docker compose pull" -ScriptBlock {
            Set-Location $deployDir
            docker compose pull 2>&1
        }
    } catch {
        Write-Warn "docker compose pull failed — will try starting anyway."
    }

    Write-Info "Starting OpenClaw containers..."
    try {
        $proc = Start-Process -FilePath "docker" `
            -ArgumentList "compose", "--project-directory", $deployDir, "up", "-d" `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput "$env:TEMP\docker_out.tmp" `
            -RedirectStandardError  "$env:TEMP\docker_err.tmp"
        Get-Content "$env:TEMP\docker_out.tmp" -ErrorAction SilentlyContinue |
            Out-File -Append -FilePath $script:INSTALL_LOG
        Get-Content "$env:TEMP\docker_err.tmp" -ErrorAction SilentlyContinue |
            Out-File -Append -FilePath $script:INSTALL_LOG
        if ($proc.ExitCode -ne 0) {
            throw "docker compose up exited with code $($proc.ExitCode)"
        }
    } catch {
        throw "Failed to start Docker containers: $_"
    }

    Write-Success "OpenClaw containers started from $deployDir"
}

function Install-OpenClaw-WSL2 {
    Write-Info "Launching the Linux EasyClaw installer inside WSL2..."
    Write-Host ""
    Write-Host "  This will run the following inside your default WSL2 distribution:" -ForegroundColor DarkGray
    Write-Host "  curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-YesNo -Prompt "Proceed?" -Default $true
    if (-not $confirm) {
        throw "WSL2 install cancelled by user."
    }

    # Pass any pre-filled values as environment variables into WSL
    $envVars = ""
    if ($script:PROVIDER -ne "")       { $envVars += "EASYCLAW_PROVIDER='$script:PROVIDER' " }
    if ($script:API_KEY -ne "")        { $envVars += "EASYCLAW_API_KEY='$script:API_KEY' " }
    if ($script:ASSISTANT_NAME -ne "") { $envVars += "EASYCLAW_NAME='$script:ASSISTANT_NAME' " }

    $wslCmd = "curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | ${envVars}bash"

    Write-Info "Switching to WSL2..."
    Write-Host ""
    # Run interactively — no -NoNewWindow so user sees the bash output
    Start-Process -FilePath "wsl.exe" -ArgumentList "--", "bash", "-c", $wslCmd -Wait -NoNewWindow
    Write-Host ""
    Write-Success "WSL2 install completed. OpenClaw is running inside your WSL2 environment."
    Write-Info "Access the dashboard from Windows at: http://localhost:$script:OPENCLAW_PORT"
    exit 0
}

# ==============================================================================
# STEP 6: CONFIGURE CHANNELS
# ==============================================================================
function Step6-ConfigureChannels {
    Write-Step -Number 6 -Total 8 -Message "Configuring channels"

    if ($script:CHANNELS.Count -eq 0) {
        Write-Info "No channels configured — web dashboard only."
        return
    }

    # For native mode the config is already written with channel tokens.
    # For docker mode, .env is already written.
    # We just confirm here and mention how to add more later.

    Write-Success "Channel configuration complete:"
    foreach ($ch in $script:CHANNELS) {
        Write-Success "  - $ch"
    }

    Write-Info "To add more channels later, run: easyclaw channels add"
}

# ==============================================================================
# STEP 7: VERIFY & CELEBRATE
# ==============================================================================
function Step7-VerifyAndCelebrate {
    Write-Step -Number 7 -Total 8 -Message "Verifying installation"

    $allOk = $true

    switch ($script:INSTALL_MODE) {
        "native" {
            # Check openclaw --version
            Refresh-Path
            $oclawCmd = Get-Command openclaw -ErrorAction SilentlyContinue
            if ($oclawCmd) {
                $ver = (openclaw --version 2>$null | Select-Object -First 1)
                Write-Success "openclaw --version: $ver"
            } else {
                Write-Warn "openclaw command not found in PATH yet (will work in new PowerShell window)"
                $allOk = $false
            }

            # Run openclaw doctor if available
            if ($oclawCmd) {
                Write-Info "Running openclaw doctor..."
                try {
                    $doctorOut = openclaw doctor 2>&1
                    $doctorOut | Out-File -Append -FilePath $script:INSTALL_LOG
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "openclaw doctor: all checks passed"
                    } else {
                        Write-Warn "openclaw doctor reported warnings — check log for details"
                    }
                } catch {
                    Write-Warn "openclaw doctor not available yet — run it manually after restart"
                }
            }

            # Check config file exists
            $cfgFile = Join-Path $script:OPENCLAW_CONFIG_DIR "openclaw.json"
            if (Test-Path $cfgFile) {
                Write-Success "Config file: $cfgFile"
            } else {
                Write-Warn "Config file not found at $cfgFile"
                $allOk = $false
            }
        }

        "docker" {
            # Check containers are running
            $containers = docker ps --filter "name=openclaw" --format "{{.Names}}" 2>$null
            if ($containers -like "*openclaw*") {
                Write-Success "Docker container 'openclaw' is running"
            } else {
                Write-Warn "OpenClaw container not found running — it may be starting up"
                $allOk = $false
            }

            # Wait for health check
            Write-Info "Waiting for OpenClaw to be ready (up to 30 seconds)..."
            $ready   = $false
            $elapsed = 0
            while (-not $ready -and $elapsed -lt 30) {
                try {
                    $resp = Invoke-WebRequest -Uri "http://localhost:$script:OPENCLAW_PORT/api/health" `
                        -UseBasicParsing -ErrorAction SilentlyContinue -TimeoutSec 3
                    if ($resp.StatusCode -eq 200) { $ready = $true }
                } catch { }
                if (-not $ready) { Start-Sleep -Seconds 2; $elapsed += 2 }
            }
            if ($ready) {
                Write-Success "OpenClaw health check passed"
            } else {
                Write-Warn "OpenClaw health endpoint not responding yet — it may need more time to start"
            }
        }
    }

    # ---- Celebration box ----
    Write-Host ""
    $celebLines = @(
        "                                       ",
        "   OpenClaw is installed!              ",
        "---",
        "   Dashboard:  http://localhost:$script:OPENCLAW_PORT  ",
        "   Config dir: $script:OPENCLAW_CONFIG_DIR ",
        "   Install log: $script:INSTALL_LOG   ",
        "---"
    )

    if ($script:INSTALL_MODE -eq "native") {
        $celebLines += "   Quick commands:                     "
        $celebLines += "     openclaw start     - start daemon "
        $celebLines += "     openclaw stop      - stop daemon  "
        $celebLines += "     openclaw status    - check status "
        $celebLines += "     openclaw doctor    - diagnostics  "
        $celebLines += "     easyclaw --help    - EasyClaw CLI "
    } elseif ($script:INSTALL_MODE -eq "docker") {
        $deployDir = Join-Path $env:USERPROFILE "easyclaw"
        $celebLines += "   Quick commands:                     "
        $celebLines += "     docker compose -f $deployDir\docker-compose.yml ps"
        $celebLines += "     docker compose -f $deployDir\docker-compose.yml logs -f"
        $celebLines += "     easyclaw --help    - EasyClaw CLI "
    }

    $celebLines += "---"
    $celebLines += "   Thank you for using EasyClaw!     "
    $celebLines += "   https://github.com/YashasVM/easyclaw "

    Write-Box -Lines $celebLines -Width 54
    Write-Host ""

    Write-Host ""
    Write-Host "  Open your dashboard in a browser:" -ForegroundColor DarkGray
    Write-Host "  http://localhost:$script:OPENCLAW_PORT" -ForegroundColor Cyan
    Write-Host ""
}

# ==============================================================================
# STEP 8: INSTALL EASYCLAW CLI
# ==============================================================================
function Step8-InstallEasyClawCLI {
    Write-Step -Number 8 -Total 8 -Message "Installing EasyClaw CLI"

    # Determine install location — use a user-writable directory
    $easyclawDir = Join-Path $env:USERPROFILE ".easyclaw" "bin"
    if (-not (Test-Path $easyclawDir)) {
        New-Item -Path $easyclawDir -ItemType Directory -Force | Out-Null
    }

    $ps1Dest = Join-Path $easyclawDir "easyclaw.ps1"
    $cmdDest = Join-Path $easyclawDir "easyclaw.cmd"

    # Copy this script to the bin directory
    $selfPath = $MyInvocation.MyCommand.Path
    if ($selfPath -and (Test-Path $selfPath)) {
        Copy-Item -Path $selfPath -Destination $ps1Dest -Force
        Write-Success "Copied easyclaw.ps1 -> $ps1Dest"
    } else {
        # Script was piped/run from memory — write a launcher stub
        $launcherContent = @"
#Requires -Version 5.1
# EasyClaw CLI launcher — generated by install.ps1
param([Parameter(ValueFromRemainingArguments)][string[]]`$args)
`$ErrorActionPreference = 'Stop'
Write-Host 'EasyClaw v$script:EASYCLAW_VERSION' -ForegroundColor Cyan
Write-Host 'Usage: easyclaw [start|stop|status|doctor|update|channels]' -ForegroundColor DarkGray
"@
        Set-Content -Path $ps1Dest -Value $launcherContent -Encoding UTF8
        Write-Info "Created easyclaw.ps1 launcher at $ps1Dest"
    }

    # Create .cmd wrapper so it works from cmd.exe too
    $cmdContent = @"
@echo off
REM EasyClaw CLI wrapper for cmd.exe
REM Generated by EasyClaw installer v$script:EASYCLAW_VERSION
powershell.exe -ExecutionPolicy Bypass -File "%~dp0easyclaw.ps1" %*
"@
    Set-Content -Path $cmdDest -Value $cmdContent -Encoding ASCII
    Write-Success "Created cmd wrapper: $cmdDest"

    # Add to user PATH if not already there
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$easyclawDir*") {
        $newPath = if ($userPath) { "$userPath;$easyclawDir" } else { $easyclawDir }
        [System.Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Success "Added $easyclawDir to user PATH"
        Write-Warn "PATH update takes effect in new PowerShell / cmd windows."
    } else {
        Write-Success "EasyClaw bin dir already in PATH: $easyclawDir"
    }

    # Also update current session PATH
    $env:PATH = "$env:PATH;$easyclawDir"

    Write-Info "EasyClaw CLI installed at: $ps1Dest"
    Write-Info "cmd.exe wrapper at:        $cmdDest"
    Write-Host ""
    Write-Host "  Usage (after opening a new terminal):" -ForegroundColor DarkGray
    Write-Host "    easyclaw --help" -ForegroundColor Cyan
}

# ==============================================================================
# ERROR HANDLER — catch-all
# ==============================================================================
function Show-FriendlyError {
    param([string]$Message, [int]$Step = 0)

    Write-Host ""
    Write-Host "" 
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║        Something went wrong  :(          ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Error: " -ForegroundColor Red -NoNewline
    Write-Host $Message -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  What to do:" -ForegroundColor Yellow
    Write-Host "    1. Read the full log:  $script:INSTALL_LOG" -ForegroundColor White
    Write-Host "    2. Share that file when asking for help." -ForegroundColor White
    Write-Host "    3. Try running the failed step manually." -ForegroundColor White
    Write-Host ""

    if ($Step -gt 0) {
        Write-Host "  Failed at Step $Step." -ForegroundColor DarkGray
    }

    Write-Host "  Log saved to: $script:INSTALL_LOG" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Get help: https://github.com/YashasVM/easyclaw/issues" -ForegroundColor DarkGray
    Write-Host ""
}

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================
function Main {
    # Initialize log
    "=" * 60 | Out-File -Append -FilePath $script:INSTALL_LOG
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] EasyClaw installer starting (PowerShell $($PSVersionTable.PSVersion))" |
        Out-File -Append -FilePath $script:INSTALL_LOG
    "=" * 60 | Out-File -Append -FilePath $script:INSTALL_LOG

    # ---- Show banner ----
    Show-Banner

    # ---- STEP 1 ----
    try {
        Step1-DetectEnvironment
    } catch {
        Show-FriendlyError -Message $_.Exception.Message -Step 1
        exit 1
    }

    # ---- STEP 2 ----
    try {
        Step2-ChooseMode
    } catch {
        Show-FriendlyError -Message $_.Exception.Message -Step 2
        exit 1
    }

    # ---- STEP 3 ----
    try {
        Step3-InstallDependencies
    } catch {
        Show-FriendlyError -Message $_.Exception.Message -Step 3
        exit 1
    }

    # ---- STEP 4 (skip if WSL2 — linux installer handles it) ----
    if ($script:INSTALL_MODE -ne "wsl2") {
        try {
            Step4-Configure
        } catch {
            Show-FriendlyError -Message $_.Exception.Message -Step 4
            exit 1
        }
    }

    # ---- STEP 5 ----
    try {
        Step5-InstallOpenClaw
    } catch {
        Show-FriendlyError -Message $_.Exception.Message -Step 5
        exit 1
    }

    # ---- STEP 6 ----
    try {
        Step6-ConfigureChannels
    } catch {
        Show-FriendlyError -Message $_.Exception.Message -Step 6
        exit 1
    }

    # ---- STEP 7 ----
    try {
        Step7-VerifyAndCelebrate
    } catch {
        Show-FriendlyError -Message $_.Exception.Message -Step 7
        exit 1
    }

    # ---- STEP 8 ----
    try {
        Step8-InstallEasyClawCLI
    } catch {
        # Non-fatal — CLI install failure shouldn't abort everything
        Write-Warn "EasyClaw CLI install failed: $($_.Exception.Message)"
        Write-Warn "OpenClaw itself is still installed and running."
    }

    Write-Host ""
    Write-Host "  All done! Enjoy OpenClaw." -ForegroundColor Green
    Write-Host ""
}

# ---- Run ----
Main
