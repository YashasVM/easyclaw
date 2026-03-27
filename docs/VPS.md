# VPS Deployment Guide

This guide covers deploying OpenClaw on a Virtual Private Server (VPS) using EasyClaw's **Full Server** mode, which sets up Docker + Caddy (automatic HTTPS) + systemd for a production-grade deployment.

---

## Table of Contents

- [Recommended VPS Providers](#recommended-vps-providers)
- [Minimum Requirements](#minimum-requirements)
- [Step 1 — Provision Your Server](#step-1--provision-your-server)
- [Step 2 — Initial Server Setup](#step-2--initial-server-setup)
- [Step 3 — Domain & DNS Setup](#step-3--domain--dns-setup)
- [Step 4 — Configure Firewall](#step-4--configure-firewall)
- [Step 5 — Run EasyClaw](#step-5--run-easyclaw)
- [Step 6 — Verify Everything Works](#step-6--verify-everything-works)
- [Monitoring Tips](#monitoring-tips)

---

## Recommended VPS Providers

All three providers below work great with EasyClaw. Prices are approximate and change over time — check each provider's current pricing page.

### Hetzner Cloud
- **Best for:** European users, best price-to-performance ratio
- **Recommended plan:** CX22 (2 vCPU, 4GB RAM, 40GB NVMe) — ~€4/month
- **Website:** [hetzner.com/cloud](https://www.hetzner.com/cloud)
- **Pros:** Excellent performance, very affordable, clean UI, good API
- **Cons:** Fewer US data center locations

### DigitalOcean
- **Best for:** US/global users, beginner-friendly, good documentation
- **Recommended plan:** Basic Droplet (2 vCPU, 2GB RAM, 50GB SSD) — ~$12/month
- **Website:** [digitalocean.com](https://www.digitalocean.com)
- **Pros:** Great docs, one-click Docker installs, reliable support
- **Cons:** Slightly pricier than Hetzner for equivalent specs

### Contabo
- **Best for:** Budget-conscious deployments needing more RAM
- **Recommended plan:** VPS S (4 vCPU, 8GB RAM, 100GB NVMe) — ~€6/month
- **Website:** [contabo.com](https://contabo.com)
- **Pros:** Extremely cheap for the specs, good for heavier workloads
- **Cons:** Slower provisioning, support response times can vary

---

## Minimum Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 1 vCPU | 2 vCPU |
| RAM | 1GB | 2GB |
| Disk | 10GB | 20GB |
| OS | Ubuntu 20.04 | Ubuntu 22.04 LTS |
| Network | Any | 100 Mbps+ |

> **Note:** The 1GB RAM minimum is tight. If you plan to run multiple channels or expect heavy usage, go with at least 2GB.

---

## Step 1 — Provision Your Server

### On Hetzner:
1. Log in at [console.hetzner.cloud](https://console.hetzner.cloud).
2. Click **New Server**.
3. Choose a location (Nuremberg, Helsinki, or Ashburn).
4. Select image: **Ubuntu 22.04**.
5. Choose type: **CX22** or better.
6. Under **SSH Keys**, add your public SSH key (recommended) or use a root password.
7. Click **Create & Buy Now**.
8. Note the server's **public IP address**.

### On DigitalOcean:
1. Log in and click **Create → Droplets**.
2. Choose **Ubuntu 22.04 (LTS) x64**.
3. Select the **Basic** plan, **Regular CPU**, 2GB RAM option.
4. Choose a datacenter region close to your users.
5. Add your SSH key under **Authentication**.
6. Click **Create Droplet**.
7. Note the Droplet's **IP address**.

---

## Step 2 — Initial Server Setup

SSH into your new server as root:

```bash
ssh root@YOUR_SERVER_IP
```

### Create a non-root user (recommended)

Running everything as root is not ideal. Create a dedicated user:

```bash
# Create a new user (replace "deploy" with any username you like)
adduser deploy

# Give them sudo access
usermod -aG sudo deploy

# Copy your SSH key to the new user
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy

# Switch to the new user
su - deploy
```

### Update the system

```bash
sudo apt update && sudo apt upgrade -y
```

### Install basic tools

```bash
sudo apt install -y curl git ufw
```

---

## Step 3 — Domain & DNS Setup

For Full Server mode with automatic HTTPS, you need a domain name pointing to your server's IP.

### If you already have a domain:

1. Log in to your domain registrar (Namecheap, Cloudflare, GoDaddy, etc.).
2. Go to **DNS settings** for your domain.
3. Add an **A record**:
   - **Name:** `@` (for root domain) or a subdomain like `ai` or `bot`
   - **Value:** your server's public IP address
   - **TTL:** 300 (5 minutes) or Auto

**Examples:**
```
Type  Name    Value             TTL
A     @       203.0.113.42      300    → resolves as yourdomain.com
A     ai      203.0.113.42      300    → resolves as ai.yourdomain.com
```

4. Wait for DNS to propagate — usually 2–10 minutes, sometimes up to an hour.

### Verify DNS is working:

```bash
# From your local machine or the server
nslookup yourdomain.com
# or
dig +short yourdomain.com
```

It should return your server's IP address.

> **Tip:** You can check propagation status at [dnschecker.org](https://dnschecker.org).

---

## Step 4 — Configure Firewall

Set up `ufw` (Uncomplicated Firewall) to block unnecessary ports:

```bash
# Allow SSH (critical — do this first or you'll lock yourself out)
sudo ufw allow OpenSSH

# Allow HTTP (needed for Caddy's HTTPS certificate challenge)
sudo ufw allow 80/tcp

# Allow HTTPS
sudo ufw allow 443/tcp

# Enable the firewall
sudo ufw enable

# Verify the rules
sudo ufw status
```

Expected output:
```
Status: active

To                         Action      From
--                         ------      ----
OpenSSH                    ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
```

> **Important:** Do NOT open port 18789 publicly. Caddy handles all traffic on 443/80 and forwards it to OpenClaw on 18789 internally. Exposing 18789 directly would bypass Caddy's security headers and HTTPS.

---

## Step 5 — Run EasyClaw

Now you're ready to install. Run the EasyClaw installer on your server:

```bash
curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash
```

When prompted:

1. **Deployment mode** → choose `Full Server`
2. **Domain** → enter your domain name (e.g., `ai.yourdomain.com`)
3. **AI provider** → choose your provider and enter your API key
4. **Channels** → set up whichever channels you want
5. The installer will:
   - Install Docker
   - Install Caddy
   - Generate all config files
   - Create and enable a systemd service
   - Start the gateway
   - Obtain a free HTTPS certificate from Let's Encrypt

### Non-interactive (automated) install:

```bash
EASYCLAW_MODE=full \
EASYCLAW_DOMAIN=ai.yourdomain.com \
EASYCLAW_PROVIDER=anthropic \
EASYCLAW_API_KEY=sk-ant-xxx \
EASYCLAW_CHANNELS=telegram \
EASYCLAW_TELEGRAM_TOKEN=123:ABC \
curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash
```

---

## Step 6 — Verify Everything Works

### Check service status

```bash
easyclaw status
```

You should see something like:
```
EasyClaw Status
───────────────────────────────────────
Mode:       Full Server (Docker + Caddy)
Gateway:    ✅ Running  (healthy)
Caddy:      ✅ Running
Systemd:    ✅ Enabled  (openclaw.service)
HTTPS:      ✅ https://ai.yourdomain.com
Channels:   Telegram ✅
───────────────────────────────────────
```

### Test the HTTPS endpoint

```bash
curl -fsS https://ai.yourdomain.com/healthz
```

You should get a `200 OK` response.

### Test a channel

Send a message to your bot via whichever channel you configured. You should get an AI reply within a few seconds.

---

## Monitoring Tips

### View live logs

```bash
# OpenClaw gateway logs
easyclaw logs

# Caddy logs
sudo journalctl -u caddy -f

# systemd service logs
sudo journalctl -u openclaw -f
```

### Check resource usage

```bash
# See memory and CPU usage by container
docker stats

# Check disk usage
df -h
du -sh ~/.easyclaw/
```

### Set up automatic updates

EasyClaw can check for OpenClaw updates on a schedule. Add this to your crontab:

```bash
crontab -e
```

Add this line to update every Sunday at 3am:
```
0 3 * * 0 easyclaw update --yes >> /var/log/easyclaw-update.log 2>&1
```

### Set up log rotation

EasyClaw uses Docker's built-in log rotation (configured in `docker-compose.yml` with `max-size: 10m, max-file: 3`), so logs won't fill up your disk. To check current log sizes:

```bash
docker system df
```

### Disk space alerts

If your disk gets low, EasyClaw's workspace directory is usually the culprit. You can clean old conversation data:

```bash
easyclaw backup       # back up first
easyclaw clean        # remove old workspace data
```

### Uptime monitoring

For peace of mind, consider a free uptime monitor like [UptimeRobot](https://uptimerobot.com) or [Betteruptime](https://betterstack.com/better-uptime). Point it at `https://ai.yourdomain.com/healthz` — it'll alert you if your bot goes down.
