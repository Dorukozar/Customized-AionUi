# Codebase Structure

**Analysis Date:** 2026-03-17

## Directory Layout

```
aionui-custom/
├── src/
│   ├── index.ts                   # Electron main process entry
│   ├── preload.ts                 # Electron contextBridge preload script
│   ├── adapter/                   # Process-specific IPC adapter implementations
│   ├── agent/                     # AI agent client libraries (run in worker processes)
│   │   ├── acp/                   # ACP (Anthropic Claude Protocol) agent
│   │   ├── codex/                 # Codex agent (connection, core, handlers, messaging)
│   │   ├── gemini/                # Gemini CLI agent + tools
│   │   ├── nanobot/               # NanoBot agent
│   │   └── openclaw/              # OpenClaw agent
│   ├── channels/                  # Multi-platform IM channel subsystem
│   │   ├── core/                  # ChannelManager, SessionManager
│   │   ├── gateway/               # ActionExecutor, PluginManager
│   │   ├── agent/                 # ChannelEventBus, ChannelMessageService
│   │   ├── actions/               # system/platform/chat action handlers
│   │   ├── pairing/               # User authorization pairing codes
│   │   ├── plugins/               # Platform plugin implementations
│   │   │   ├── telegram/          # TelegramPlugin + Adapter + Keyboards
│   │   │   ├── lark/              # LarkPlugin + Adapter + Cards
│   │   │   └── dingtalk/          # DingTalkPlugin + Adapter + Cards
│   │   └── utils/                 # credentialCrypto, misc utils
│   ├── common/                    # Shared across all process types
│   │   ├── ipcBridge.ts           # ALL typed IPC channel definitions
│   │   ├── storage.ts             # Core storage types (TChatConversation, IProvider…)
│   │   ├── adapters/              # Storage/model adapters
│   │   ├── approval/              # Tool confirmation approval helpers
│   │   ├── codex/                 # Codex-specific shared types and utils
│   │   ├── types/                 # Shared TypeScript types
│   │   └── utils/                 # Shared utility functions
│   ├── extensions/                # Extension/plugin loading system
│   │   ├── ExtensionRegistry.ts   # Singleton registry; scans and loads extensions
│   │   ├── ExtensionLoader.ts     # Loads individual extension bundles
│   │   ├── sandbox.ts             # Sandboxed extension execution
│   │   └── resolvers/             # Path, env, file, entry-point resolvers
│   ├── process/                   # Electron main process logic
│   │   ├── index.ts               # initializeProcess() — storage + extensions + channels
│   │   ├── initBridge.ts          # Registers all IPC bridges + starts CronService
│   │   ├── initStorage.ts         # SQLite DB init, ProcessConfig, ProcessChat
│   │   ├── WorkerManage.ts        # Factory + registry for all AgentManager instances
│   │   ├── bridge/                # One file per IPC domain
│   │   │   ├── conversationBridge.ts
│   │   │   ├── geminiBridge.ts
│   │   │   ├── acpConversationBridge.ts
│   │   │   ├── channelBridge.ts
│   │   │   ├── cronBridge.ts
│   │   │   ├── taskBridge.ts
│   │   │   ├── authBridge.ts
│   │   │   ├── modelBridge.ts
│   │   │   ├── mcpBridge.ts
│   │   │   ├── webuiBridge.ts
│   │   │   └── ...               # 20+ bridge files total
│   │   ├── database/              # better-sqlite3 wrapper
│   │   │   ├── index.ts           # getDatabase() singleton
│   │   │   ├── schema.ts          # CREATE TABLE + indexes
│   │   │   ├── migrations.ts      # Versioned schema migrations
│   │   │   └── export.ts          # Re-exports for convenience
│   │   ├── i18n/                  # Main process i18n (separate from renderer)
│   │   ├── services/              # Background services
│   │   │   ├── cron/              # CronService + CronBusyGuard (croner-based)
│   │   │   ├── mcpServices/       # MCP protocol client management
│   │   │   ├── autoUpdaterService.ts
│   │   │   └── conversationService.ts
│   │   └── task/                  # AgentManager implementations
│   │       ├── BaseAgentManager.ts
│   │       ├── GeminiAgentManager.ts
│   │       ├── AcpAgentManager.ts
│   │       ├── CodexAgentManager.ts
│   │       ├── NanoBotAgentManager.ts
│   │       └── OpenClawAgentManager.ts
│   ├── renderer/                  # React UI (Electron renderer process)
│   │   ├── index.ts               # React root mount + provider setup
│   │   ├── index.html             # HTML shell
│   │   ├── main.tsx               # Top-level Main component (auth gate)
│   │   ├── layout.tsx             # App shell layout (sider + content + tray events)
│   │   ├── router.tsx             # HashRouter + all page routes
│   │   ├── sider.tsx              # Left sidebar navigation
│   │   ├── assets/                # Images, logos, channel logos
│   │   ├── bootstrap/             # Runtime patches applied before React mounts
│   │   ├── components/            # Shared UI components
│   │   │   ├── base/              # Generic base components
│   │   │   ├── SettingsModal/     # Settings modal with tabbed contents
│   │   │   ├── Titlebar/          # Custom window titlebar
│   │   │   ├── UpdateModal/       # Auto-update notification modal
│   │   │   └── ...
│   │   ├── config/                # Static renderer configuration
│   │   ├── constants/             # Renderer-specific constants
│   │   ├── context/               # React contexts
│   │   │   ├── AuthContext.tsx    # Auth state + login/logout
│   │   │   ├── ThemeContext.tsx   # Dark/light theme
│   │   │   ├── ConversationContext.tsx
│   │   │   └── LayoutContext.tsx
│   │   ├── hooks/                 # Shared custom hooks
│   │   │   └── mcp/               # MCP-related hooks
│   │   ├── i18n/                  # react-i18next setup + locale files
│   │   │   └── locales/           # en-US, zh-CN, zh-TW, ja-JP, ko-KR, tr-TR
│   │   ├── messages/              # Message rendering components
│   │   │   ├── acp/               # ACP message components
│   │   │   └── codex/             # Codex message + ToolCallComponent
│   │   ├── pages/                 # Route-level page components
│   │   │   ├── conversation/      # Main chat page
│   │   │   │   ├── index.tsx      # Conversation page root
│   │   │   │   ├── acp/           # ACP-specific conversation UI
│   │   │   │   ├── codex/         # Codex-specific conversation UI
│   │   │   │   ├── gemini/        # Gemini-specific conversation UI
│   │   │   │   ├── nanobot/       # NanoBot conversation UI
│   │   │   │   ├── openclaw/      # OpenClaw conversation UI
│   │   │   │   ├── components/    # Shared chat components
│   │   │   │   ├── context/       # ConversationTabsContext
│   │   │   │   ├── hooks/         # Chat-specific hooks
│   │   │   │   ├── preview/       # File/code preview panel
│   │   │   │   └── workspace/     # Workspace file browser
│   │   │   ├── cron/              # Scheduled task management page
│   │   │   ├── guid/              # New conversation / agent selector page
│   │   │   ├── login/             # Authentication page (WebUI mode)
│   │   │   ├── settings/          # All settings pages
│   │   │   │   ├── AgentSettings.tsx
│   │   │   │   ├── DisplaySettings.tsx
│   │   │   │   ├── GeminiSettings.tsx
│   │   │   │   ├── ModeSettings.tsx
│   │   │   │   ├── SystemSettings.tsx
│   │   │   │   ├── WebuiSettings.tsx
│   │   │   │   ├── McpManagement/
│   │   │   │   ├── CustomAcpAgent/
│   │   │   │   └── ExtensionSettingsPage.tsx
│   │   │   └── test/              # ComponentsShowcase (dev only)
│   │   ├── services/              # Renderer service classes
│   │   │   ├── FileService.ts
│   │   │   └── PasteService.ts
│   │   ├── shared/                # Renderer-specific shared code
│   │   │   └── agents/            # availableAgents, preset resources, agent types
│   │   ├── styles/                # Global styles + theme color schemes
│   │   │   └── themes/
│   │   ├── theme/                 # Theme utility functions
│   │   ├── types/                 # Renderer-specific TypeScript types
│   │   └── utils/                 # Renderer utility functions
│   ├── shared/                    # Truly cross-cutting shared config
│   │   └── i18n-config.json
│   ├── shims/                     # Shim modules for incompatible packages
│   │   └── xterm-headless.ts      # Replaces @xterm/headless in browser builds
│   ├── types/                     # Top-level TypeScript declarations
│   ├── utils/                     # Main process startup utilities
│   │   ├── appMenu.ts             # Native application menu setup
│   │   ├── configureChromium.ts   # CDP / remote debugging setup
│   │   ├── configureConsoleLog.ts # electron-log integration
│   │   └── shellEnv.ts            # Shell PATH resolution (nvm, etc.)
│   └── webserver/                 # Express + WebSocket server (WebUI mode)
│       ├── index.ts               # startWebServer(), startWebServerWithInstance()
│       ├── adapter.ts             # Bridges webserver to main process services
│       ├── auth/                  # JWT auth (service, repository, middleware)
│       ├── config/                # Constants (DEFAULT_PORT, AUTH_CONFIG)
│       ├── middleware/            # Express middleware (rate limit, etc.)
│       ├── routes/                # authRoutes, apiRoutes, staticRoutes
│       ├── types/                 # Express type extensions
│       └── websocket/             # WebSocketManager for real-time AI chat
├── tests/
│   ├── unit/                      # Unit tests — functions, utilities, components
│   ├── integration/               # Integration tests — IPC, DB, service interactions
│   ├── regression/                # Regression test cases
│   ├── e2e/                       # Playwright end-to-end tests
│   ├── vitest.setup.ts            # Node environment test setup
│   └── vitest.dom.setup.ts        # jsdom environment test setup
├── examples/                      # Example extension packages
│   ├── hello-world-extension/     # Minimal extension skeleton
│   ├── e2e-full-extension/        # Full-featured extension for E2E tests
│   ├── acp-adapter-extension/     # ACP adapter example
│   ├── ext-feishu/                # Feishu/Lark external extension example
│   └── ext-wecom-bot/             # WeCom bot external extension example
├── assistant/                     # Built-in assistant definition files (JSON/YAML)
├── skills/                        # Built-in skill definitions
├── rules/                         # Built-in rule files
├── docs/
│   ├── tech/architecture.md       # High-level architecture overview
│   └── plans/                     # Implementation planning docs
├── scripts/                       # Build/maintenance scripts
│   └── check-i18n.js              # Validates i18n key completeness across locales
├── resources/                     # App icons (app.png, app.ico, app_dev.png)
├── public/                        # Static assets served by Vite renderer
├── .planning/codebase/            # GSD codebase analysis documents
├── src/index.ts                   # Main process entry (Electron)
├── electron.vite.config.ts        # Build config (main + preload + renderer + workers)
├── electron-builder.yml           # Packaging config
├── tsconfig.json                  # TypeScript config (strict mode)
├── vitest.config.ts               # Vitest test runner config
├── playwright.config.ts           # Playwright E2E config
├── uno.config.ts                  # UnoCSS atomic CSS config
├── package.json                   # Deps, scripts
└── bun.lock                       # Lockfile (Bun package manager)
```

## Directory Purposes

**`src/process/bridge/`:**
- Purpose: One file per IPC domain — each file exports `init<Domain>Bridge()` which registers provider and emitter handlers
- Key files: `conversationBridge.ts`, `geminiBridge.ts`, `channelBridge.ts`, `cronBridge.ts`
- All bridges are wired together in `src/process/bridge/index.ts` via `initAllBridges()`

**`src/common/ipcBridge.ts`:**
- Purpose: Single source of truth for ALL IPC channel names and type signatures
- Must be updated when adding any new IPC channel — both `buildProvider` definition here AND the bridge handler in `src/process/bridge/`

**`src/process/task/`:**
- Purpose: AgentManager classes that manage forked worker processes for each agent type
- Key file: `BaseAgentManager.ts` — extends `ForkTask`, handles yolo mode, confirmation queue

**`src/renderer/pages/conversation/`:**
- Purpose: Main conversation UI; per-agent subdirectories contain agent-specific rendering
- Each agent type (gemini, acp, codex, nanobot, openclaw) has its own subdirectory for agent-specific UI

**`src/renderer/i18n/locales/`:**
- Purpose: Translation files organized by language then module
- Pattern: `<lang>/<module>.json` — e.g., `en-US/conversation.json`, `zh-CN/settings.json`
- `en-US` is the reference locale; all other locales must have identical keys

**`src/channels/`:**
- Purpose: IM channel integration; entirely within main process
- Architecture documented in `src/channels/ARCHITECTURE.md`

**`src/extensions/`:**
- Purpose: Extension registry and loader; scans the `extensions/` user data directory and built-in extension paths

**`src/webserver/`:**
- Purpose: Optional Express server for headless/remote usage; shares the main process Node runtime

## Key File Locations

**Entry Points:**
- `src/index.ts`: Electron main entry, app lifecycle, window creation
- `src/renderer/index.ts`: React app mount
- `src/preload.ts`: `contextBridge` API exposure
- `src/worker/gemini.ts`, `acp.ts`, `codex.ts`, `openclaw-gateway.ts`, `nanobot.ts`: Worker entries

**Configuration:**
- `electron.vite.config.ts`: Build configuration, path aliases, manual chunk splitting
- `tsconfig.json`: TypeScript strict config with path aliases
- `vitest.config.ts`: Test runner, coverage, environment definitions
- `uno.config.ts`: UnoCSS atomic CSS rules

**Core Logic:**
- `src/common/ipcBridge.ts`: All IPC channel definitions
- `src/process/WorkerManage.ts`: Agent task factory and registry
- `src/process/database/schema.ts`: Database schema (SQLite tables + indexes)
- `src/process/database/migrations.ts`: Versioned migrations
- `src/process/bridge/index.ts`: `initAllBridges()` wiring

**Testing:**
- `tests/unit/`: Co-located logic tests
- `tests/integration/`: IPC and service integration tests
- `tests/e2e/`: Playwright tests (uses `examples/e2e-full-extension/`)
- `vitest.config.ts`: Test configuration, coverage include patterns

## Naming Conventions

**Files:**
- React components: `PascalCase.tsx` (e.g., `ChatLayout.tsx`, `UpdateModal.tsx`)
- Non-component TypeScript: `camelCase.ts` or `PascalCase.ts` for classes (e.g., `conversationBridge.ts`, `GeminiAgentManager.ts`)
- CSS modules: `*.module.css` alongside their component
- Bridge files: `<domain>Bridge.ts` pattern (e.g., `conversationBridge.ts`, `channelBridge.ts`)

**Directories:**
- `kebab-case` for multi-word directories (e.g., `grouped-history/`, `mcpServices/`)
- Singular for single-concern directories (`hook`, `utils`, `types`)

**Path Aliases (configured in `electron.vite.config.ts` and `tsconfig.json`):**
- `@/*` → `src/*`
- `@common/*` → `src/common/*`
- `@renderer/*` → `src/renderer/*`
- `@process/*` → `src/process/*`
- `@worker/*` → `src/worker/*`

## Where to Add New Code

**New IPC feature (e.g., a new main-process capability):**
1. Add channel definition to `src/common/ipcBridge.ts` using `bridge.buildProvider` or `bridge.buildEmitter`
2. Create `src/process/bridge/<domain>Bridge.ts` implementing the handler
3. Register it in `src/process/bridge/index.ts` → `initAllBridges()`
4. Call from renderer via `ipcBridge.<domain>.<channel>.invoke()` or `.on()`

**New agent type:**
1. Add agent client library in `src/agent/<name>/`
2. Add worker entry at `src/worker/<name>.ts`
3. Add `AgentManager` class at `src/process/task/<Name>AgentManager.ts` extending `BaseAgentManager`
4. Register in `WorkerManage.buildConversation()` switch statement (`src/process/WorkerManage.ts`)
5. Add worker entry to `electron.vite.config.ts` rollupOptions inputs
6. Add conversation type to `schema.ts` CHECK constraint

**New renderer page:**
- Implementation: `src/renderer/pages/<page-name>/index.tsx`
- Route: Add lazy import + `<Route>` in `src/renderer/router.tsx`
- Navigation: Add entry to `src/renderer/sider.tsx`

**New shared component:**
- Implementation: `src/renderer/components/<ComponentName>/<ComponentName>.tsx`
- Styles (if scoped): `src/renderer/components/<ComponentName>/<ComponentName>.module.css`

**New IPC domain bridge file:**
- Implementation: `src/process/bridge/<domain>Bridge.ts`
- Registration: `src/process/bridge/index.ts`

**New i18n text:**
- Add key to all locale files: `src/renderer/i18n/locales/<lang>/<module>.json`
- Run `node scripts/check-i18n.js` to verify completeness
- Run `bun run i18n:types` to regenerate type definitions

**Utilities:**
- Shared (main + renderer): `src/common/utils/`
- Renderer-only: `src/renderer/utils/`
- Main-only: `src/process/utils/` or `src/utils/` (startup utilities)

**New Channel (IM platform):**
- Implementation: `src/channels/plugins/<platform>/` (Plugin, Adapter, Cards)
- Register in `src/channels/gateway/PluginManager.ts` plugin registry
- Add platform type to `PluginType` union in `src/channels/types.ts`

## Special Directories

**`src/worker/fork/`:**
- Purpose: `ForkTask` base class used by all AgentManagers to spawn/communicate with worker processes
- Generated: No
- Committed: Yes

**`skills/`:**
- Purpose: Built-in skill definition files loaded by agents at runtime
- Generated: No
- Committed: Yes; copied to build output by `viteStaticCopy` in production

**`assistant/`:**
- Purpose: Built-in assistant preset definitions (JSON/YAML); packaged with app
- Generated: No
- Committed: Yes

**`rules/`:**
- Purpose: Built-in rule files for agent behavior; packaged with app
- Generated: No
- Committed: Yes

**`.planning/codebase/`:**
- Purpose: GSD codebase analysis documents consumed by `/gsd:plan-phase` and `/gsd:execute-phase`
- Generated: Yes (by `/gsd:map-codebase`)
- Committed: Yes

**`examples/`:**
- Purpose: Reference extension implementations and E2E test fixtures
- Generated: No
- Committed: Yes

---

*Structure analysis: 2026-03-17*
