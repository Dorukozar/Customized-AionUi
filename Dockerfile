# Diador — AionUi Docker image
# Base: debian:bookworm-slim (glibc required — Alpine/musl breaks Electron + better-sqlite3)

FROM debian:bookworm-slim

# System dependencies for Electron / Chromium headless
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Chromium / Electron runtime deps
    libgtk-3-0 \
    libnss3 \
    libgbm1 \
    libasound2 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libxss1 \
    libxtst6 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libpango-1.0-0 \
    libcairo2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgcc-s1 \
    libglib2.0-0 \
    libnspr4 \
    libxcb1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxkbcommon0 \
    # Utilities
    curl \
    unzip \
    ca-certificates \
    # Node.js native addon build deps (better-sqlite3)
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /app

# Install dependencies first (layer caching)
COPY package.json bun.lock ./
COPY patches/ patches/
RUN bun install --frozen-lockfile --ignore-scripts

# Copy source and build
COPY . .

# Download Electron binary (skipped by --ignore-scripts)
RUN node node_modules/electron/install.js

# Rebuild native modules for Electron's Node headers
RUN node scripts/postinstall.js
RUN bun run make

# Expose WebUI port
EXPOSE 25808

# Launch in WebUI mode with remote access (headless auto-detected via missing DISPLAY)
# Do NOT use --headless — it triggers browser automation mode and causes auto-exit
CMD ["npx", "electron", ".", "--webui", "--remote", "--no-sandbox", "--ozone-platform=headless", "--disable-gpu", "--disable-software-rasterizer"]
