# OpenClaw Docker image for getsetclaw

Docker image that runs [OpenClaw](https://docs.clawd.bot/) (Node + openclaw). Used by [getsetclaw](https://getsetclaw.com) so each user gets a dedicated instance deployed on Hetzner (one VM per customer), reachable at **http://&lt;VM_IP&gt;/**. Configuration is fully dynamic from environment variables (Telegram token and optional agents come from your SaaS/Inngest).

## Image contents

- **Node 22** (OpenClaw requires Node ≥22)
- **OpenClaw** (`openclaw` npm package, latest)
- **Gateway** listens on port **18789** inside the container (map to host **80** for direct IP access)
- Config is generated at startup from env; no tenant-specific data in the image

## Build and run locally

```bash
# Build
docker build -t openclaw-node .

# Run (gateway on host port 80)
docker run -d --name openclaw -p 80:18789 \
  -e TELEGRAM_ENABLED=true \
  -e TELEGRAM_BOT_TOKEN=your_bot_token \
  -e TELEGRAM_ALLOW_FROM='*' \
  openclaw-node
```

Or with Compose:

```bash
cp .env.example .env   # set TELEGRAM_BOT_TOKEN etc.
docker compose up -d
```

Then open **http://localhost/** (or http://localhost:80). Health: the gateway serves its endpoints on that port.

## Environment variables (for Inngest / Hetzner)

| Variable | Description |
|----------|-------------|
| `OPENCLAW_PORT` | Gateway port inside container (default `18789`) |
| `OPENCLAW_HOME` | Home dir for `~/.openclaw` (default `/app`) |
| `TELEGRAM_ENABLED` | Set to `true` to enable Telegram (default on if `TELEGRAM_BOT_TOKEN` is set) |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token (from getsetclaw per user) |
| `TELEGRAM_ALLOW_FROM` | Comma-separated user IDs or `*` for open DMs |
| `TELEGRAM_DM_POLICY` | `pairing` (default) or `allowlist` / `open` |
| `OPENCLAW_AGENTS_JSON` | Optional JSON object merged into `channels` (e.g. Discord, Slack) |
| `OPENCLAW_MODEL_ID` | Primary model id (default `anthropic/claude-sonnet-4-5`) |
| `OPENCLAW_MODEL_ENV_KEY` | Env var name for the API key (e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) |
| `OPENCLAW_MODEL_API_KEY` | API key value (injected into config `env.vars`) |
| `OPENCLAW_MODEL_PROVIDER_ID` | Optional custom provider id (e.g. `openrouter`) |
| `OPENCLAW_MODEL_BASE_URL` | Optional provider base URL (e.g. `https://openrouter.ai/api/v1`) |

Example extra channels (JSON string):

```bash
OPENCLAW_AGENTS_JSON='{"discord":{"enabled":true,"token":"..."}}'
```

## Publish to GitHub Container Registry (GHCR)

1. Push to `main` or create a tag `v*` (e.g. `v1.0.0`).
2. The workflow [.github/workflows/publish-image.yml](.github/workflows/publish-image.yml) builds and pushes to **ghcr.io/&lt;owner&gt;/&lt;repo&gt;:latest** and **:&lt;sha&gt;** (and **:v*** on tag push).
3. Image is **public**; no login needed to pull.

Use the image name in Hetzner/Inngest, e.g.:

```text
ghcr.io/YOUR_ORG/clawdeploy-docker:latest
```

## Deploy on Hetzner (one VM per user)

Use [scripts/hetzner-cloud-init.sh](scripts/hetzner-cloud-init.sh) as the basis for Hetzner user-data. Your Inngest function (on Vercel) should:

1. Create a Hetzner VM with this script as user-data.
2. Replace the placeholders at the top of the script (or pass env) with the tenant’s values:
   - `GHCR_IMAGE` – e.g. `ghcr.io/YOUR_ORG/clawdeploy-docker:latest`
   - `TELEGRAM_BOT_TOKEN` – from your SaaS DB
   - `TELEGRAM_ALLOW_FROM` – `*` or the user’s Telegram ID(s)
   - `OPENCLAW_AGENTS_JSON` – optional extra channels
3. After the VM boots, get its **public IP** from the Hetzner API and store it (e.g. as `openclawBaseUrl = "http://<IP>/"`) for the user and for Telegram (long-polling works by default; no webhook required).

User-facing URL: **http://&lt;VM_PUBLIC_IP&gt;/**

## Direct IP access (no domain)

- Each tenant’s OpenClaw runs on one VM; the container listens on 18789, mapped to host **80**.
- No DNS or reverse proxy in this setup; users and Telegram use the VM’s public IP over HTTP.
- To add a domain or HTTPS later, put a reverse proxy (e.g. nginx/Caddy) or load balancer in front and point it at the VM.

## License

Same as the repo / getsetclaw.
