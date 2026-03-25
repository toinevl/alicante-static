# OpenClaw — Ubuntu Install with Container-per-Agent

This directory contains everything you need to install [OpenClaw](https://github.com/openclaw/openclaw) on a Ubuntu PC with each agent running in its own isolated Docker container.

## Architecture

```
Ubuntu host OS
├── OpenClaw Gateway (systemd user service, port 18789)
│   └── per-agent session → spawns Docker container (openclaw-sandbox:latest)
│                                └── shell / file / browser tools run here
├── ~/.openclaw/config.yaml   ← your config
└── ~/openclaw/workspace/     ← shared workspace (mounted into each container)
```

The gateway itself runs directly on the host. Every time an agent session starts, the gateway launches a **fresh, isolated Docker container** for that agent's tool execution. When the session ends the container is automatically removed.

## Quick Start

### 1. Run the setup script

```bash
chmod +x openclaw/setup.sh
./openclaw/setup.sh
```

This will:
- Install Docker CE
- Install Node.js 24 via nvm
- Install `openclaw` globally via npm
- Build the sandbox Docker image
- Write a default config to `~/.openclaw/config.yaml`
- Install the OpenClaw gateway as a systemd user service

### 2. Configure

Edit `~/.openclaw/config.yaml` and fill in:

| Setting | Description |
|---|---|
| `model.provider` | Your AI provider (`anthropic`, `openai`, etc.) |
| `model.name` | Model name, e.g. `claude-sonnet-4-6` |
| `model.api_key` | Your API key (or set `OPENCLAW_API_KEY` env var) |
| `channels.*` | Telegram / Discord / Slack tokens |
| `security.allowlist` | Your messaging username(s) |

### 3. Log out and back in

The Docker group change requires a new login session:

```bash
# or without logging out:
newgrp docker
```

### 4. Start the gateway

```bash
systemctl --user start openclaw-gateway

# Follow logs
journalctl --user -u openclaw-gateway -f
```

### 5. Open the web UI

```
http://localhost:18789
```

## Sandbox Image

The `Dockerfile.sandbox` defines the container environment each agent runs in. Customise it to add tools your agents need (e.g. Python packages, CLI tools), then rebuild:

```bash
docker build -t openclaw-sandbox:latest -f openclaw/Dockerfile.sandbox openclaw/
```

## Useful Commands

```bash
# Check gateway status
systemctl --user status openclaw-gateway

# Stop / restart
systemctl --user stop openclaw-gateway
systemctl --user restart openclaw-gateway

# List running agent containers
docker ps --filter label=openclaw.session

# Run OpenClaw doctor
openclaw doctor

# Update OpenClaw
openclaw update --channel stable
```

## Security Notes

- The gateway only listens on `127.0.0.1`. **Never expose port 18789 to the internet.**
- Sandbox containers run as a non-root `agent` user.
- `exec.ask: "on"` requires you to approve shell/write commands before they execute.
- The `security.pairing` setting prevents unknown users from controlling your agents.
