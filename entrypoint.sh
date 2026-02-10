#!/bin/sh
set -e

# OpenClaw expects config under ~/.openclaw
export HOME="${OPENCLAW_HOME:-/app}"
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
WORKSPACE="${OPENCLAW_WORKSPACE:-$CONFIG_DIR/workspace}"
PORT="${OPENCLAW_PORT:-18789}"

mkdir -p "$CONFIG_DIR" "$WORKSPACE"

# Build minimal config: agent workspace + gateway (local, bind lan for external access)
config() {
  cat <<EOF
{
  "agents": {
    "defaults": {
      "workspace": "$WORKSPACE"
    }
  },
  "gateway": {
    "mode": "local",
    "port": $PORT,
    "bind": "lan"
  },
  "channels": {}
}
EOF
}

# Write base config and then merge in channels via node (to support JSON merge)
write_config() {
  config > "$CONFIG_FILE.base"
  CONFIG_PATH="$CONFIG_FILE" node -e "
    const fs = require('fs');
    const basePath = process.env.CONFIG_PATH + '.base';
    const outPath = process.env.CONFIG_PATH;
    let c = JSON.parse(fs.readFileSync(basePath, 'utf8'));
    c.channels = c.channels || {};

    // Telegram: enabled by default when TELEGRAM_BOT_TOKEN is set
    const telegramEnabled = process.env.TELEGRAM_ENABLED !== 'false' && process.env.TELEGRAM_BOT_TOKEN;
    if (telegramEnabled) {
      const allowFrom = process.env.TELEGRAM_ALLOW_FROM || '*';
      c.channels.telegram = {
        enabled: true,
        botToken: process.env.TELEGRAM_BOT_TOKEN,
        dmPolicy: (process.env.TELEGRAM_DM_POLICY || 'pairing'),
        allowFrom: allowFrom === '*' ? ['*'] : allowFrom.split(',').map(s => s.trim()).filter(Boolean),
        groups: { '*': { requireMention: true } }
      };
    }

    // Extra agents/channels from SaaS (e.g. Discord, Slack) – merge into channels
    const extra = process.env.OPENCLAW_AGENTS_JSON;
    if (extra) {
      try {
        const add = JSON.parse(extra);
        if (typeof add === 'object' && add !== null) {
          Object.assign(c.channels, add);
        }
      } catch (e) {
        console.error('Invalid OPENCLAW_AGENTS_JSON:', e.message);
      }
    }

    // Dynamic model: primary model ID (per tenant)
    const modelId = process.env.OPENCLAW_MODEL_ID || 'anthropic/claude-sonnet-4-5';
    c.agents = c.agents || {};
    c.agents.defaults = c.agents.defaults || {};
    c.agents.defaults.model = { primary: modelId };

    // Inject API key into env.vars so OpenClaw can use it (per tenant)
    const envKey = process.env.OPENCLAW_MODEL_ENV_KEY;
    const apiKey = process.env.OPENCLAW_MODEL_API_KEY;
    if (envKey && apiKey) {
      c.env = c.env || {};
      c.env.vars = c.env.vars || {};
      c.env.vars[envKey] = apiKey;
    }

    // Optional: custom provider (e.g. OpenRouter) with base URL
    const providerId = process.env.OPENCLAW_MODEL_PROVIDER_ID;
    const baseUrl = process.env.OPENCLAW_MODEL_BASE_URL;
    if (providerId && baseUrl) {
      c.models = c.models || {};
      c.models.mode = c.models.mode || 'merge';
      c.models.providers = c.models.providers || {};
      c.models.providers[providerId] = {
        baseUrl: baseUrl,
        apiKey: envKey ? '\${' + envKey + '}' : undefined,
        api: 'openai-responses'
      };
    }

    fs.writeFileSync(outPath, JSON.stringify(c, null, 2));
  "
  rm -f "$CONFIG_FILE.base"
}

write_config

exec openclaw gateway --port "$PORT" --verbose "$@"
