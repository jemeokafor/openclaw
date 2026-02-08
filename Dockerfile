FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Allow non-root user to write temp files during runtime/tests.
RUN chown -R node:node /app

# Keep root at runtime so mounted volumes (e.g. Railway /data) are writable.
# Non-root containers often cannot write fresh volume mounts without an init chown step.

# Start gateway with Railway-friendly defaults.
# - bind: lan (0.0.0.0)
# - port: PORT env (defaults to 8080)
# - state/workspace: /data paths when not explicitly provided
CMD ["bash", "-lc", "set -euo pipefail; export OPENCLAW_STATE_DIR=\"${OPENCLAW_STATE_DIR:-/data/.openclaw}\"; export OPENCLAW_WORKSPACE_DIR=\"${OPENCLAW_WORKSPACE_DIR:-/data/workspace}\"; export PORT=\"${PORT:-8080}\"; mkdir -p \"$OPENCLAW_STATE_DIR\" \"$OPENCLAW_WORKSPACE_DIR\"; if [ -z \"${OPENCLAW_GATEWAY_TOKEN:-}\" ] && [ -z \"${OPENCLAW_GATEWAY_PASSWORD:-}\" ]; then echo \"ERROR: set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD for --bind lan\" >&2; exit 1; fi; exec node openclaw.mjs gateway --allow-unconfigured --bind lan --port \"$PORT\""]
