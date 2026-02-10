# OpenClaw gateway image for getsetclaw SaaS (Node 22 + openclaw)
# Config is built at runtime from env vars; no tenant-specific data in the image.
FROM node:22-alpine

RUN apk add --no-cache dumb-init

# OpenClaw state and config live under /app (HOME set at runtime)
ENV APP_DIR=/app
WORKDIR $APP_DIR

# Install OpenClaw globally (Node 22+ required per docs)
RUN npm install -g openclaw@latest

# Create dirs for config and workspace (entrypoint will write openclaw.json)
RUN mkdir -p $APP_DIR/.openclaw/workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Gateway default port (map to host 80 for direct IP access)
ENV OPENCLAW_PORT=18789
EXPOSE $OPENCLAW_PORT

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/entrypoint.sh"]
