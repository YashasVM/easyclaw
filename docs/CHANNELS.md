# Channel Setup Guide

This guide walks you through connecting OpenClaw (via EasyClaw) to each supported messaging platform. Follow the steps for whichever channels you want to use. You can always add more channels later by running `easyclaw channels`.

---

## Table of Contents

- [Telegram](#telegram)
- [Discord](#discord)
- [WhatsApp](#whatsapp)
- [Slack](#slack)

---

## Telegram

Telegram is the easiest channel to set up. You'll create a "bot" using Telegram's official BotFather tool, then give EasyClaw the bot's token.

### Step 1 — Open BotFather

1. Open Telegram (app or [web.telegram.org](https://web.telegram.org)).
2. In the search bar at the top, search for **@BotFather**.
3. Tap the verified result (it has a blue checkmark) and tap **Start**.

> **What you'll see:** A welcome message listing all available BotFather commands.

### Step 2 — Create a new bot

1. Type `/newbot` and send it.
2. BotFather will ask: **"Alright, a new bot. How are we going to call it?"** — enter a display name for your assistant (e.g., `My AI Assistant`). This is just a label.
3. Next it asks for a **username** — this must be unique and end in `bot` (e.g., `myai_assistant_bot`). Try a few options if your first choice is taken.

> **What you'll see:** Once accepted, BotFather replies with a message containing your bot's **HTTP API token** — a long string that looks like `123456789:ABCdefGHIjklMNOpqrSTUvwxYZ`.

### Step 3 — Copy your token

Copy the entire token from BotFather's reply. You'll paste it into EasyClaw's installer prompt or set it as `EASYCLAW_TELEGRAM_TOKEN`.

### Step 4 — (Optional) Customize your bot

While still in BotFather, you can:
- `/setdescription` — set a short bio for your bot
- `/setuserpic` — upload a profile photo
- `/setcommands` — define slash commands your bot responds to

These are optional. Your bot will work fine without them.

### Step 5 — Start your bot

1. Search for your new bot's username in Telegram.
2. Open the chat and tap **Start**.
3. Send a test message. If OpenClaw is running, you should get a reply.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| "Unauthorized" error | Double-check that you copied the full token with no extra spaces |
| Bot doesn't respond | Run `easyclaw status` and `easyclaw logs` to check if the gateway is running |
| "Bot not found" when searching | Make sure you're searching by the exact `@username` you chose |
| Token expired | Go back to BotFather and use `/token` to generate a new one |

---

## Discord

You'll create a Discord "application" in the Developer Portal and invite it to your server as a bot.

### Step 1 — Go to the Discord Developer Portal

1. Visit [discord.com/developers/applications](https://discord.com/developers/applications).
2. Log in with your Discord account.
3. Click **New Application** in the top-right corner.
4. Give it a name (e.g., `My AI Assistant`) and click **Create**.

### Step 2 — Create a bot user

1. In the left sidebar, click **Bot**.
2. Click **Add Bot**, then confirm with **Yes, do it!**
3. Under the bot's username, click **Reset Token** → **Yes, do it!** to generate your bot token.
4. Copy the token and store it somewhere safe — Discord will only show it once.

> **Security tip:** Never commit this token to Git. Treat it like a password.

### Step 3 — Set bot permissions

1. Still on the Bot page, scroll down to **Privileged Gateway Intents**.
2. Enable:
   - **Message Content Intent** (required to read messages)
   - **Server Members Intent** (optional, for member-related features)
3. Click **Save Changes**.

### Step 4 — Invite the bot to your server

1. In the left sidebar, click **OAuth2** → **URL Generator**.
2. Under **Scopes**, check `bot`.
3. Under **Bot Permissions**, check:
   - `Read Messages / View Channels`
   - `Send Messages`
   - `Read Message History`
4. Copy the generated URL at the bottom and open it in your browser.
5. Select the server you want to invite the bot to, then click **Authorize**.

### Step 5 — Configure EasyClaw

Paste your bot token when EasyClaw prompts for it, or set `EASYCLAW_DISCORD_TOKEN=your-token-here`.

### Step 6 — Test it

Go to your Discord server, find the channel where the bot has access, and send a message mentioning it (e.g., `@MyAIAssistant hello!`). You should get a response.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| Bot shows as offline | Check `easyclaw logs` — the gateway may not be running |
| "Missing Access" error | Make sure the bot was invited with `Read Messages` permission |
| Bot ignores messages | Ensure **Message Content Intent** is enabled in the Developer Portal |
| "Invalid Token" error | Regenerate the token in the Developer Portal and update your config |

---

## WhatsApp

WhatsApp uses a QR code pairing method — no developer account required. Your phone acts as the bridge.

> **Important:** Keep your phone connected to the internet and plugged in while running OpenClaw. If your phone loses its WhatsApp session, the bot will stop working until you re-scan the QR code.

### Step 1 — Start the OpenClaw WhatsApp setup

During EasyClaw installation, when you select WhatsApp as a channel, the installer will:
1. Start the OpenClaw gateway.
2. Display a **QR code** in your terminal.

If you need to re-scan later, run:
```bash
easyclaw channels
```
and select WhatsApp.

### Step 2 — Scan the QR code with your phone

1. Open **WhatsApp** on your phone.
2. Tap the **three-dot menu** (Android) or **Settings** (iPhone).
3. Tap **Linked Devices** → **Link a Device**.
4. Point your camera at the QR code in your terminal.

> **What you'll see:** WhatsApp will say "Linking..." and then confirm success. The QR code in your terminal will disappear and the gateway will log that the connection is established.

### Step 3 — Test it

Send a message to the WhatsApp number that is now linked. You should receive a reply from OpenClaw.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| QR code expires before you scan | It refreshes every 20 seconds — wait for a new one to appear |
| "Session disconnected" after a while | Your phone may have turned off Wi-Fi. Re-run `easyclaw channels` to re-scan |
| Bot replies from a number you don't recognize | That's your linked number — it's normal |
| Multiple devices conflict | WhatsApp allows up to 4 linked devices. If full, remove one via Linked Devices settings |

---

## Slack

You'll create a Slack app and install it to your workspace.

### Step 1 — Create a Slack app

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App**.
2. Choose **From scratch**.
3. Enter an **App Name** (e.g., `OpenClaw Assistant`) and select your **workspace**.
4. Click **Create App**.

### Step 2 — Configure bot permissions

1. In the left sidebar, click **OAuth & Permissions**.
2. Scroll down to **Bot Token Scopes** and click **Add an OAuth Scope**.
3. Add these scopes:
   - `chat:write` — to send messages
   - `channels:history` — to read channel messages
   - `im:history` — to read direct messages
   - `im:write` — to send direct messages
   - `app_mentions:read` — to receive @mentions

### Step 3 — Enable event subscriptions

1. In the left sidebar, click **Event Subscriptions** and toggle **Enable Events** on.
2. In the **Request URL** field, enter your OpenClaw gateway webhook URL:
   ```
   https://your-domain.com/slack/events
   ```
   (If using Quick Install without a domain, you'll need a tool like [ngrok](https://ngrok.com/) for local testing.)
3. Under **Subscribe to Bot Events**, add:
   - `message.channels`
   - `message.im`
   - `app_mention`
4. Click **Save Changes**.

### Step 4 — Install the app to your workspace

1. In the left sidebar, click **Install App**.
2. Click **Install to Workspace** and authorize.
3. Copy the **Bot User OAuth Token** (starts with `xoxb-`).

### Step 5 — Configure EasyClaw

Paste the `xoxb-` token when EasyClaw prompts, or set `EASYCLAW_SLACK_TOKEN=xoxb-your-token`.

### Step 6 — Test it

1. In Slack, invite the bot to a channel: `/invite @OpenClawAssistant`
2. Mention the bot: `@OpenClawAssistant hello!`
3. You should receive a reply.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| "not_authed" error | Check that you're using the `xoxb-` Bot Token, not the app token |
| Bot doesn't respond to messages | Verify that Event Subscriptions are enabled and the scopes are correct |
| "channel_not_found" | Make sure you've invited the bot to the channel with `/invite` |
| Events not reaching OpenClaw | Check that your Request URL is accessible from the internet and returns 200 |

---

## Adding More Channels Later

You can add or reconfigure channels at any time without reinstalling:

```bash
easyclaw channels
```

This re-runs the interactive channel setup and restarts OpenClaw with the new configuration.
