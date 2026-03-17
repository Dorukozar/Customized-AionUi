# External Integrations

**Analysis Date:** 2026-03-17

## AI Model Providers

All providers are user-configured. API keys/credentials are stored in the `@office-ai/platform` storage layer (persisted JSON on disk via `src/common/storage.ts`). The full provider list is defined in `src/renderer/config/modelPlatforms.ts`.

**Anthropic (Claude):**
- Direct API: `@anthropic-ai/sdk@^0.71.2`
- Base URL: `https://api.anthropic.com`
- Auth: API key stored in `model.config` storage
- Used in: `src/agent/acp/` (ACP backend), direct chat conversations

**ACP (AI Command Protocol) Agents:**
- SDK: `@office-ai/aioncli-core@^0.30.0`
- Purpose: Wraps agentic CLI tools (Claude Code, iFlow, CodeBuddy, etc.) as long-running worker processes
- Workers: `src/worker/acp.ts`, `src/worker/codex.ts`, `src/worker/gemini.ts`, `src/worker/nanobot.ts`, `src/worker/openclaw-gateway.ts`
- Agent adapters: `src/agent/acp/`, `src/agent/codex/`, `src/agent/gemini/`, `src/agent/nanobot/`, `src/agent/openclaw/`
- Auth: configurable per backend (`authToken`, `authMethodId`) in `acp.config` storage key

**Google Gemini:**
- SDK: `@google/genai@^1.16.0`
- Base URL: `https://generativelanguage.googleapis.com`
- Auth types: API key OR Google OAuth (Vertex AI)
- Vertex AI: requires `GOOGLE_CLOUD_PROJECT` / per-account project ID
- Config: `gemini.config` storage key in `src/common/storage.ts`
- Worker: `src/worker/gemini.ts`

**AWS Bedrock:**
- SDK: `@aws-sdk/client-bedrock@^3.987.0`
- Auth: AWS credentials (access key/secret) stored in `model.config`
- Accessed via platform type `'bedrock'` in `src/renderer/config/modelPlatforms.ts`

**OpenAI and OpenAI-compatible providers:**
- SDK: `openai@^5.12.2`
- Covers: OpenAI, DeepSeek, OpenRouter, Dashscope (Qwen), SiliconFlow, Zhipu, Moonshot, xAI, Ark (Volcengine), Qianfan (Baidu), Hunyuan (Tencent), Lingyi, Poe, PPIO, ModelScope, InfiniAI, Ctyun, StepFun, MiniMax
- All use platform type `'custom'` with preset `baseUrl` values
- Auth: API key per provider in `model.config` storage

**New API gateway:**
- Platform type `'new-api'` in `src/renderer/config/modelPlatforms.ts`
- Auto-detects protocol (openai/gemini/anthropic) from model name via `detectNewApiProtocol()`

## MCP (Model Context Protocol)

**Purpose:** Integrates external tool servers that expose tools to the AI agents.

**SDK:** `@modelcontextprotocol/sdk@^1.20.0`

**Implementation:**
- Service: `src/process/services/mcpServices/McpService.ts`
- Protocol: `src/process/services/mcpServices/McpProtocol.ts`
- OAuth: `src/process/services/mcpServices/McpOAuthService.ts`
- Agent-specific MCP: `src/process/services/mcpServices/agents/`
- Config: `mcp.config` storage key (array of `IMcpServer`)
- UI management: `src/renderer/pages/settings/McpManagement/`

## Messaging Channel Integrations

All channel integrations are optional plugins, enabled/disabled by the user. Credentials are encrypted before SQLite storage (`src/channels/utils/credentialCrypto.ts`).

**Telegram:**
- SDK: `grammy@^1.39.3` + `@grammyjs/transformer-throttler@^1.2.1`
- Plugin: `src/channels/plugins/telegram/TelegramPlugin.ts`
- Auth: Bot token (encrypted in `assistant_plugins` table)
- Direction: Incoming messages from Telegram users → AI response → reply via bot

**Lark / Feishu:**
- SDK: `@larksuiteoapi/node-sdk@^1.58.0`
- Plugin: `src/channels/plugins/lark/`
- Auth: App ID + App Secret (encrypted in DB)

**DingTalk:**
- SDK: `dingtalk-stream@^2.1.4`
- Plugin: `src/channels/plugins/dingtalk/`
- Auth: Client ID + Client Secret (encrypted in DB)

**Channel architecture:**
- Base class: `src/channels/plugins/BasePlugin.ts`
- Core lifecycle: `src/channels/core/`
- Gateway: `src/channels/gateway/`
- User pairing (authorization flow): `src/channels/pairing/`
- Channel data stored in SQLite tables: `assistant_plugins`, `assistant_users`, `assistant_sessions`, `assistant_pairing_codes`

## Data Storage

**Primary Database:**
- SQLite via `better-sqlite3@^12.4.1`
- File path: `{userData}/aionui.db` (resolved by `getDataPath()` in `src/process/utils/`)
- Managed by: `src/process/database/index.ts` (`AionUIDatabase` singleton)
- Tables: `users`, `conversations`, `messages`, `assistant_plugins`, `assistant_users`, `assistant_sessions`, `assistant_pairing_codes`
- Schema versioning with migrations: `src/process/database/migrations/`
- Credentials in `assistant_plugins` are encrypted at rest

**Configuration/Settings Storage:**
- `@office-ai/platform` `storage` abstraction — persisted JSON files on disk
- Accessed via: `src/common/storage.ts` (typed key-value with namespaced keys)
- Covers: model configs, MCP server list, theme, language, WebUI settings, cron config, etc.

**File Storage:**
- Local filesystem only — no cloud file storage
- Workspace files accessed via Node.js `fs` in main process
- `sharp@^0.34.3` for image resizing before sending to AI models

**Caching:**
- In-memory only (no Redis/Memcache)
- `swr@^2.3.6` for renderer-side request deduplication/caching

## Authentication and Identity

**WebUI Auth (custom implementation):**
- Service: `src/webserver/auth/service/AuthService.ts`
- Repository: `src/webserver/auth/repository/UserRepository.ts`
- Password hashing: `bcryptjs` (12 salt rounds)
- Tokens: `jsonwebtoken` — JWT signed with per-installation secret stored in SQLite
- JWT secret: stored in `users.jwt_secret` column, overridable via `JWT_SECRET` env var
- Token blacklist: in-memory `Map` cleared on restart
- Session expiry: configured in `src/webserver/config/constants.ts` (`AUTH_CONFIG.TOKEN.SESSION_EXPIRY`)
- CSRF: `tiny-csrf@^1.1.6`
- Routes: `src/webserver/routes/authRoutes.ts`

**WebSocket Auth:**
- Reuses the same JWT (audience: `aionui-webui`) via `AuthService.verifyWebSocketToken()`

## Update Distribution

**Auto-update:**
- `electron-updater@^6.6.2` — checks and downloads updates from GitHub Releases
- Provider: GitHub (`iOfficeAI/AionUi`)
- Service: `src/process/services/autoUpdaterService.ts`
- Update bridge: `src/process/bridge/updateBridge.ts`
- Platform-specific channels for macOS arm64 and Windows arm64 (see `getUpdateChannel()`)

## Monitoring and Observability

**Error Tracking:**
- No external error tracking service (no Sentry, Datadog, etc.)

**Logs:**
- `electron-log@^5.4.3` — structured logging to file (main process)
- `src/utils/configureConsoleLog.ts` — console log configuration
- Performance debug: enabled via `ACP_PERF=1` env var, report via `scripts/debug-performance.ts`

## WebUI / HTTP Server

**Purpose:** Exposes a web-accessible UI and REST API when running in `--webui` mode.

**Stack:** Express 5 + WebSocket (ws 8) running inside the Electron main process

**Routes:**
- `src/webserver/routes/apiRoutes.ts` — REST API (guarded by `TokenMiddleware`)
- `src/webserver/routes/authRoutes.ts` — login/logout/refresh endpoints
- `src/webserver/routes/staticRoutes.ts` — serves renderer bundle for browser access

**Security middleware:**
- `src/webserver/middleware/security.ts` — rate limiting via `express-rate-limit`
- `TokenMiddleware` — JWT auth middleware applied to API routes
- CSRF protection on state-mutating endpoints

## CI/CD and Deployment

**Hosting:**
- Desktop app distributed as signed installers (macOS dmg, Windows NSIS, Linux deb)
- Published to GitHub Releases via `electron-builder` (`provider: github`)

**Build scripts:**
- `scripts/build-with-builder.js` — cross-platform build orchestration
- `scripts/afterPack.js`, `scripts/afterSign.js` — post-pack/sign hooks (notarization)
- `@electron/notarize@^3.1.0` — macOS App Store notarization

**CI Pipeline:**
- No CI config found in repo (no `.github/workflows/`, no `.travis.yml`)

## Environment Configuration

**Required variables (for specific features):**
- `JWT_SECRET` — optional override for JWT signing secret (WebUI mode)
- `ELECTRON_CACHE` — optional path for caching Electron downloads during build
- `NODE_ENV` — `production` switches WebUI into production mode

**Secrets location:**
- Channel credentials: encrypted in SQLite `assistant_plugins.config` column
- Model API keys: stored in `@office-ai/platform` storage JSON files on disk (not encrypted at OS level)
- JWT secret: stored in SQLite `users.jwt_secret` column

## Webhooks and Callbacks

**Incoming:**
- No HTTP webhooks — messaging channels use polling/persistent connections (grammy polling for Telegram, DingTalk stream, Lark long-connection)

**Outgoing:**
- None — no outbound webhooks defined

---

*Integration audit: 2026-03-17*
