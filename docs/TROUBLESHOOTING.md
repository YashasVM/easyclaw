# Troubleshooting Guide

Something's not working? This guide covers the most common issues people run into with EasyClaw and OpenClaw. Work through the relevant section and you'll likely find your fix.

**First, always run this:**
```bash
easyclaw status
easyclaw logs
```

These two commands reveal most problems immediately.

---

## Table of Contents

- ["command not found" after install](#command-not-found-after-install)
- [Node.js version issues](#nodejs-version-issues)
- [Docker permission errors](#docker-permission-errors)
- [Port 18789 already in use](#port-18789-already-in-use)
- [API key not working](#api-key-not-working)
- [Channel connection failures](#channel-connection-failures)
- [Gateway won't start](#gateway-wont-start)
- [WSL2 specific issues](#wsl2-specific-issues)
- [Windows-specific issues](#windows-specific-issues)
- [General diagnostics checklist](#general-diagnostics-checklist)

---

## "command not found" / "not recognized" after install

**Symptom:** You ran the EasyClaw installer and it finished successfully, but typing `easyclaw` gives `command not found`.

**Why it happens:** The installer adds `easyclaw` to your PATH by modifying `~/.bashrc` or `~/.zshrc`, but your current terminal session hasn't reloaded that file yet.

**Fix:**

```bash
# For bash users:
source ~/.bashrc

# For zsh users (macOS default):
source ~/.zshrc

# Or just close and reopen your terminal
```

Then try:
```bash
easyclaw status
```

**Still not working?** Check if the binary exists:

```bash
ls ~/.easyclaw/bin/easyclaw
```

If the file is there but still not found, add it manually:

```bash
export PATH="$HOME/.easyclaw/bin:$PATH"
echo 'export PATH="$HOME/.easyclaw/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## Node.js version issues

**Symptom:** The installer fails with an error like `"Unsupported engine"`, `"Node.js version X is too old"`, or `"SyntaxError: Unexpected token"`.

**Why it happens:** OpenClaw requires Node.js 18 or later. Many systems (especially Ubuntu 20.04) ship with an older version.

**Check your current version:**

```bash
node --version
```

**Fix — install the correct version using nvm:**

```bash
# Install nvm (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Reload your shell
source ~/.bashrc

# Install and use Node.js 20 (LTS)
nvm install 20
nvm use 20
nvm alias default 20

# Verify
node --version   # should say v20.x.x
```

**Fix — install via apt (Ubuntu/Debian):**

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

node --version   # should say v20.x.x
```

Then re-run the EasyClaw installer:

```bash
curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash
```

---

## Docker permission errors

**Symptom:** Commands like `docker ps` or `easyclaw status` fail with:
```
permission denied while trying to connect to the Docker daemon socket
Got permission denied while connecting to /var/run/docker.sock
```

**Why it happens:** By default, only the `root` user and users in the `docker` group can talk to the Docker daemon. Your user isn't in that group yet.

**Fix:**

```bash
# Add your user to the docker group
sudo usermod -aG docker $USER

# Apply the group change to your current session
newgrp docker

# Verify it worked
docker ps
```

If `newgrp docker` doesn't work (some systems), log out and log back in fully — the group change requires a new login session.

**On WSL2:** You may also need to start the Docker daemon manually:

```bash
sudo service docker start
```

Or install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/) and enable WSL2 integration in its settings.

---

## Port 18789 already in use

**Symptom:** EasyClaw or OpenClaw fails to start with an error like:
```
Error: listen EADDRINUSE: address already in use :::18789
bind: address already in use
```

**Why it happens:** Something else on your machine is already using port 18789, or a previous OpenClaw instance didn't shut down cleanly.

**Find what's using the port:**

```bash
# On Linux/macOS:
sudo lsof -i :18789

# On Linux (alternative):
sudo ss -tlnp | grep 18789
```

**If it's a leftover OpenClaw process:**

```bash
# Stop the stale process
easyclaw stop

# Or force-kill it
sudo kill $(sudo lsof -t -i:18789)

# Then start again
easyclaw start
```

**If it's something else using the port:**

Change OpenClaw's port to something unused:

```bash
# Open your .env file
nano ~/.easyclaw/.env

# Change the port line:
OPENCLAW_PORT=18790

# Save and restart
easyclaw restart
```

---

## API key not working

**Symptom:** OpenClaw starts, but your bot replies with errors like `"Authentication error"`, `"Invalid API key"`, `"insufficient_quota"`, or just doesn't respond at all.

### Anthropic (Claude) keys

- Keys start with `sk-ant-`
- Get yours at [console.anthropic.com](https://console.anthropic.com)
- Make sure you have billing set up — a free account without payment info won't work for API calls
- Check your usage limits at [console.anthropic.com/settings/limits](https://console.anthropic.com/settings/limits)

### OpenAI keys

- Keys start with `sk-`
- Get yours at [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
- Check your usage and limits at [platform.openai.com/usage](https://platform.openai.com/usage)

### Google (Gemini) keys

- Get yours at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
- Make sure the **Generative Language API** is enabled in your Google Cloud project

### OpenRouter keys

- Get yours at [openrouter.ai/keys](https://openrouter.ai/keys)
- Check your credit balance at [openrouter.ai/activity](https://openrouter.ai/activity)

**To update your API key:**

```bash
# Open the config file
nano ~/.easyclaw/config/openclaw.json

# Find the apiKey field and replace it with your new key
# Save and restart
easyclaw restart
```

---

## Channel connection failures

**Symptom:** The gateway is running fine, but messages on a specific channel don't get a response.

### All channels

First, check the logs for errors specific to your channel:

```bash
easyclaw logs | grep -i "telegram\|discord\|whatsapp\|slack"
```

### Telegram

- **"Unauthorized"** → Your bot token is wrong. Go to BotFather, use `/token` to regenerate, and update your config.
- **Bot is online but no replies** → Make sure you started a chat with the bot first (tap Start in Telegram).
- **Webhook conflict** → If you previously set a webhook somewhere, clear it:
  ```bash
  curl "https://api.telegram.org/bot<YOUR_TOKEN>/deleteWebhook"
  ```

### Discord

- **Bot shows as offline** → The gateway is probably not running. Check `easyclaw status`.
- **Bot ignores messages** → Verify that **Message Content Intent** is enabled in the [Developer Portal](https://discord.com/developers/applications).
- **"Missing Permissions"** → Re-invite the bot to your server using the URL Generator with the correct permissions (see [CHANNELS.md](CHANNELS.md)).

### WhatsApp

- **QR code not appearing** → Run `easyclaw channels` and select WhatsApp again.
- **Session drops after a while** → Your phone's WhatsApp session expired. Re-scan the QR code with `easyclaw channels`.
- **"Phone disconnected"** → Your phone must stay connected to the internet. Check your phone's battery and Wi-Fi.

### Slack

- **"not_authed"** → Make sure you're using the Bot Token (`xoxb-...`), not the App Token.
- **Events not received** → Your server must be accessible on port 443 from the internet. Check your firewall and that Caddy is running (Full Server mode) or use ngrok for local testing.
- **"channel_not_found"** → Invite the bot to the channel: `/invite @YourBotName`

**Re-run channel setup at any time:**

```bash
easyclaw channels
```

---

## Gateway won't start

**Symptom:** `easyclaw start` hangs or fails, and the gateway never becomes healthy. `easyclaw status` shows the gateway as not running.

**Step 1 — Check logs for the specific error:**

```bash
easyclaw logs
```

Look for lines near the end with `ERROR`, `FATAL`, or `Error:`.

**Step 2 — Check if Docker is running:**

```bash
sudo systemctl status docker
# or
docker info
```

If Docker isn't running:
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

**Step 3 — Check your config file for syntax errors:**

```bash
cat ~/.easyclaw/config/openclaw.json | python3 -m json.tool
```

If it prints an error, your JSON is malformed. Re-run `easyclaw channels` to regenerate it.

**Step 4 — Check disk space:**

```bash
df -h
```

If you're at 100% disk usage, the gateway can't write logs or temporary files and may refuse to start. Free up space:

```bash
docker system prune -f     # remove unused Docker images/containers
```

**Step 5 — Try a clean restart:**

```bash
easyclaw stop
sleep 5
easyclaw start
easyclaw logs
```

**Step 6 — Reinstall (last resort):**

```bash
easyclaw backup    # back up your config first
easyclaw uninstall
curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash
```

---

## WSL2 specific issues

Running EasyClaw inside Windows Subsystem for Linux (WSL2) works well but has a few quirks.

### Docker not found or daemon not running

WSL2 doesn't automatically start the Docker daemon. You have two options:

**Option A — Use Docker Desktop (recommended):**
1. Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/).
2. In Docker Desktop settings → **Resources** → **WSL Integration** → enable integration for your distro.
3. Docker will now be available inside WSL2 automatically when Docker Desktop is running.

**Option B — Run Docker inside WSL2 directly:**
```bash
sudo apt install -y docker.io
sudo service docker start
sudo usermod -aG docker $USER
newgrp docker
```

Add this to `~/.bashrc` to auto-start Docker:
```bash
# Auto-start Docker in WSL2
if ! pgrep -x "dockerd" > /dev/null; then
    sudo service docker start > /dev/null 2>&1
fi
```

### "localhost" access from Windows browser

OpenClaw runs inside WSL2, so `localhost:18789` in your Windows browser might not work. Use the WSL2 IP instead:

```bash
# Get your WSL2 IP
hostname -I | awk '{print $1}'
```

Then access it as `http://WSL2_IP:18789` from Windows.

Alternatively, add a Windows port forwarding rule (run in PowerShell as Administrator):

```powershell
netsh interface portproxy add v4tov4 listenport=18789 listenaddress=0.0.0.0 connectport=18789 connectaddress=(wsl hostname -I)
```

### File path differences

In WSL2, your Windows files are under `/mnt/c/Users/YourName/`. For best performance, keep EasyClaw's files on the Linux filesystem (`~/.easyclaw/`), not in `/mnt/c/`. The Linux filesystem is significantly faster for file I/O.

### Terminal QR codes look garbled

If the WhatsApp QR code looks broken, try using the Windows Terminal app instead of cmd.exe or PowerShell. Make sure your font supports Unicode box-drawing characters (Cascadia Code or any Nerd Font works well).

---

## Windows-Specific Issues

### PowerShell execution policy blocks the installer

Windows blocks running scripts by default. Fix it:

```powershell
# Option 1: Bypass just for this session
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.ps1 | iex"

# Option 2: Change policy permanently (run as Administrator)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "node is not recognized" after the installer installs Node.js

The installer adds Node.js to PATH, but your current terminal doesn't know about it yet.

1. Close and reopen PowerShell / CMD
2. Or refresh PATH in the current session:
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
```

### Docker Desktop not starting

Docker Desktop on Windows requires:
- **WSL2 backend** (recommended) or Hyper-V
- Virtualization enabled in BIOS

Check virtualization:
```powershell
systeminfo | findstr /i "Virtualization"
```
If it says "Virtualization Enabled In Firmware: No", you need to enable VT-x / AMD-V in your BIOS.

### Windows Defender / antivirus blocking OpenClaw

Some antivirus software flags Node.js processes. Add exclusions for:
- `%USERPROFILE%\.openclaw\`
- `%USERPROFILE%\.easyclaw\`
- Node.js installation directory

### Using CMD instead of PowerShell

The `easyclaw` command works in both CMD and PowerShell. If it doesn't work in CMD after install, make sure the `.cmd` wrapper was created:
```cmd
where easyclaw
```
If nothing shows up, the PATH entry may be missing. Add it manually:
```cmd
setx PATH "%PATH%;%USERPROFILE%\.easyclaw\bin"
```

### Port 18789 blocked by Windows Firewall

If you need to access OpenClaw from another device on your network:
```powershell
# Run as Administrator
New-NetFirewallRule -DisplayName "OpenClaw Gateway" -Direction Inbound -Port 18789 -Protocol TCP -Action Allow
```

---

## General Diagnostics Checklist

If you're still stuck after working through the relevant section above, gather this information before asking for help:

```bash
# 1. EasyClaw status summary
easyclaw status

# 2. Last 50 lines of logs
easyclaw logs | tail -50

# 3. System info
uname -a
lsb_release -a 2>/dev/null || cat /etc/os-release

# 4. Docker version
docker --version
docker compose version

# 5. Node.js version
node --version

# 6. Disk and memory
df -h
free -h

# 7. Port check
sudo ss -tlnp | grep 18789
```

Paste this output when opening a GitHub issue at [github.com/YashasVM/easyclaw/issues](https://github.com/YashasVM/easyclaw/issues) and we'll help you sort it out.
