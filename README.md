```
  ___              _____ _                
 | __|__ _ ___ _  / ____| |               
 | _|/ _` (_-</ || |    | | __ ___      __
 |___\__,_/__/\_, | |    | |/ _` \ \ /\ / /
               __/ | |____| | (_| |\ V  V / 
              |___/ \_____|_|\__,_| \_/\_/  
```

# EasyClaw 🦞

**OpenClaw setup so easy, your grandma could do it. 🦞**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/YashasVM/easyclaw?style=social)](https://github.com/YashasVM/easyclaw/stargazers)
[![Latest Release](https://img.shields.io/github/v/release/YashasVM/easyclaw)](https://github.com/YashasVM/easyclaw/releases)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-blue)](https://www.gnu.org/software/bash/)
[![PowerShell](https://img.shields.io/badge/shell-PowerShell-blue)](https://docs.microsoft.com/en-us/powershell/)

---

## What is EasyClaw?

[OpenClaw](https://github.com/openclaw/openclaw) is a powerful self-hosted AI assistant gateway — but setting it up from scratch involves installing dependencies, wiring up configs, setting up channels, creating daemon services, and running health checks. That's a lot of steps.

**EasyClaw wraps all of that into a single command.**

It automates:

- ✅ Detecting your OS and installing the right dependencies (Node.js, Docker, curl, etc.)
- ✅ Generating a secure gateway token and all config files
- ✅ Interactively setting up messaging channels (Telegram, Discord, WhatsApp, Slack)
- ✅ Launching OpenClaw as a background daemon or Docker container
- ✅ Running post-install health checks so you know it's actually working
- ✅ Installing the `easyclaw` CLI for ongoing management

No Googling. No YAML editing. No manual systemd units. Just one command.

---

## Quick Start

### macOS / Linux / WSL2

```bash
curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.ps1 | iex
```

Or if execution policy blocks it:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.ps1 | iex"
```

The installer will walk you through everything interactively. Most people are up and running in under 5 minutes.

---

## What Does It Do?

Here's what happens when you run the installer:

```
┌─────────────────────────────────────────────────────────────┐
│                     EasyClaw Install Flow                   │
└─────────────────────────────────────────────────────────────┘

  Step 1: Detect OS & check compatibility
      │
      ▼
  Step 2: Install dependencies (Node.js, Docker, curl, jq)
      │
      ▼
  Step 3: Choose deployment mode
      │         ├── Quick Install (bare-metal, no Docker)
      │         ├── Docker        (containerized)
      │         └── Full Server   (Docker + Caddy + systemd)
      ▼
  Step 4: Configure AI provider & API key
      (Anthropic / OpenAI / Google / OpenRouter)
      │
      ▼
  Step 5: Set up messaging channels
      (Telegram / Discord / WhatsApp / Slack — pick any)
      │
      ▼
  Step 6: Launch OpenClaw + run health checks
      │
      ▼
  Step 7: Install easyclaw CLI & print summary
```

---

## Features

| Feature | Description |
|---------|-------------|
| **One-liner install** | A single `curl \| bash` command does everything |
| **Smart OS detection** | Works on Windows 10/11, macOS, Ubuntu, Debian, Fedora, Arch, and WSL2 |
| **3 deployment modes** | Bare-metal, Docker, or full production server |
| **Interactive channel setup** | Step-by-step prompts for every channel |
| **Post-install CLI** | `easyclaw` command for status, updates, backups, logs |
| **Auto health checks** | Verifies the gateway is reachable before finishing |
| **Granny-proof errors** | Plain-English error messages with suggested fixes |
| **Non-interactive mode** | Fully scriptable via environment variables |

---

## Deployment Modes

| Feature | Quick Install | Docker | Full Server | WSL2 (Windows) |
|---------|:------------:|:------:|:-----------:|:--------------:|
| Best for | Personal PC | VPS / Server | Production | Windows users |
| Platforms | All | Linux / macOS | Linux | Windows 10/11 |
| HTTPS | No | No | Yes (Caddy) | No |
| Auto-restart | Daemon | Docker restart | systemd | WSL daemon |
| Isolation | None | Container | Full | WSL sandbox |
| Recommended for beginners | ✅ | ✅ | Advanced | ✅ |

**Quick Install** — Installs OpenClaw directly on your machine using Node.js. Simplest option for personal computers. Works on Windows, macOS, and Linux.

**Docker** — Runs OpenClaw inside a Docker container. Better isolation, easy to update, great for VPS deployments without a domain.

**Full Server** — Docker + Caddy reverse proxy + systemd service. Recommended for production deployment with a domain name and automatic HTTPS. Linux only.

**WSL2 (Windows)** — The Windows installer can automatically set up WSL2 and run the Linux installer inside it. This gives you the full Linux experience on Windows with better stability.

---

## Post-Install Commands

After installation, the `easyclaw` CLI is available globally:

| Command | What it does |
|---------|-------------|
| `easyclaw status` | Show whether OpenClaw is running and which channels are connected |
| `easyclaw logs` | Tail the live OpenClaw logs |
| `easyclaw update` | Pull the latest OpenClaw image / package and restart |
| `easyclaw restart` | Restart the OpenClaw service |
| `easyclaw stop` | Stop the OpenClaw service |
| `easyclaw start` | Start a stopped OpenClaw service |
| `easyclaw backup` | Create a timestamped backup of your config and workspace |
| `easyclaw restore` | Restore from a previous backup |
| `easyclaw channels` | Re-run the interactive channel setup |
| `easyclaw uninstall` | Cleanly remove OpenClaw and all EasyClaw files |

**Examples:**

```bash
# Check if everything is healthy
easyclaw status

# View live logs
easyclaw logs

# Update to the latest version
easyclaw update

# Back up your config
easyclaw backup
# → Backup saved to ~/easyclaw-backups/backup-2026-03-27.tar.gz
```

---

## Requirements

### Linux / macOS
- **Bash 4+** — comes with Linux; macOS users may need to `brew install bash`
- **curl** — almost certainly already installed

### Windows
- **Windows 10** (build 1903+) or **Windows 11**
- **PowerShell 5.1+** — comes pre-installed with Windows 10/11
- Optional: **Windows Terminal** for a better experience

### All platforms
- **Internet connection** — to download packages and Docker images
- **An API key** from one of the supported AI providers:
  - [Anthropic (Claude)](https://console.anthropic.com/)
  - [OpenAI (GPT-4)](https://platform.openai.com/api-keys)
  - [Google (Gemini)](https://aistudio.google.com/app/apikey)
  - [OpenRouter](https://openrouter.ai/keys) — works with many models

That's it. The installer will take care of the rest.

---

## Advanced Usage

You can skip the interactive prompts entirely by setting environment variables. This is useful for automated deployments, CI/CD pipelines, or provisioning scripts.

**Linux / macOS:**

```bash
EASYCLAW_PROVIDER=anthropic \
EASYCLAW_API_KEY=sk-ant-xxx \
EASYCLAW_MODE=docker \
EASYCLAW_CHANNELS=telegram \
EASYCLAW_TELEGRAM_TOKEN=123456789:ABCdefGHIjklMNOpqrSTUvwxYZ \
curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash
```

**Windows PowerShell:**

```powershell
$env:EASYCLAW_PROVIDER = "anthropic"
$env:EASYCLAW_API_KEY = "sk-ant-xxx"
$env:EASYCLAW_MODE = "docker"
irm https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.ps1 | iex
```

### All supported environment variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `EASYCLAW_PROVIDER` | `anthropic`, `openai`, `google`, `openrouter` | (prompted) | AI provider |
| `EASYCLAW_API_KEY` | string | (prompted) | API key for the provider |
| `EASYCLAW_MODEL` | model name | provider default | Specific model to use |
| `EASYCLAW_MODE` | `quick`, `docker`, `full` | (prompted) | Deployment mode |
| `EASYCLAW_CHANNELS` | comma-separated list | (prompted) | Channels to set up |
| `EASYCLAW_TELEGRAM_TOKEN` | string | (prompted if Telegram) | Telegram bot token |
| `EASYCLAW_DISCORD_TOKEN` | string | (prompted if Discord) | Discord bot token |
| `EASYCLAW_SLACK_TOKEN` | string | (prompted if Slack) | Slack bot token |
| `EASYCLAW_DOMAIN` | hostname | (prompted if full mode) | Domain for Caddy HTTPS |
| `EASYCLAW_ASSISTANT_NAME` | string | `Assistant` | Name for the AI assistant |
| `EASYCLAW_INSTALL_DIR` | path | `~/.easyclaw` | Where to install files |

---

## Troubleshooting

### "easyclaw: command not found" after install (Linux/macOS)

Your shell hasn't reloaded yet. Run:
```bash
source ~/.bashrc
# or
source ~/.zshrc
```
Then try `easyclaw status` again.

### "easyclaw is not recognized" after install (Windows)

Close and reopen your terminal (PowerShell or CMD). The installer adds `easyclaw` to your PATH, but existing terminals need a restart to see it. If it still doesn't work:
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
```

### OpenClaw won't start / gateway health check fails

```bash
easyclaw logs
```
Look for error messages near the bottom. Common causes:
- Port 18789 is already in use → change it in your `.env` file and restart
- Invalid API key → re-run `easyclaw channels` to reconfigure

### Docker permission error

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Port 18789 already in use

```bash
# Find what's using it
sudo lsof -i :18789
# Change OpenClaw's port
nano ~/.easyclaw/.env   # Set OPENCLAW_PORT=18790
easyclaw restart
```

### Channel not receiving messages

Check the detailed channel setup guide: [docs/CHANNELS.md](docs/CHANNELS.md)

For more detailed troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## Uninstall

```bash
easyclaw uninstall
```

This will stop the service, remove all EasyClaw files, and optionally remove Docker images. Your backups (if any) are left untouched.

---

## Deploying on a VPS?

See the full VPS deployment guide: [docs/VPS.md](docs/VPS.md)

Recommended providers: Hetzner, DigitalOcean, Contabo. Minimum specs: 2 vCPU, 2GB RAM, 20GB disk.

---

## Contributing

Contributions are welcome! To get started:

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/my-improvement`
3. Make your changes and test them
4. Submit a pull request with a clear description of what you changed and why

Please keep the installer compatible with Windows 10+, Ubuntu 20.04+, Debian 11+, Fedora 36+, and macOS 12+.

For bug reports, open an issue and include the output of `easyclaw status` and your OS version.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Credits

- **OpenClaw** — the AI assistant gateway that powers everything: [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw)
- **Created by** [YashasVM](https://github.com/YashasVM)
