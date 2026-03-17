# Architecture

**Analysis Date:** 2026-03-17

## Pattern Overview

**Overall:** Multi-process Electron desktop app with layered service architecture

**Key Characteristics:**
- Three separate process types with hard boundaries enforced by Electron's security model
- All cross-process communication is typed and channeled through a single IPC bridge library (`@office-ai/platform`)
- Agent tasks run as isolated forked worker processes; the main process manages their lifecycle via `WorkerManage`
- A secondary Express+WebSocket server (`src/webserver/`) provides remote access to the same AI capabilities without the desktop UI

## Layers

**Main Process:**
- Purpose: Application lifecycle, database, IPC handler registration, service orchestration
- Location: `src/process/`
- Contains: Bridge handlers, agent managers, database access, cron service, channels subsystem
- Depends on: `better-sqlite3`, `@office-ai/platform`, agent workers (via fork)
- Used by: Renderer (via IPC), Worker processes (via fork IPC), WebServer

**Renderer Process:**
- Purpose: React UI — no Node.js APIs allowed
- Location: `src/renderer/`
- Contains: Pages, components, hooks, contexts, i18n, services
- Depends on: `window.electronAPI` (contextBridge), `@office-ai/platform` bridge (renderer side)
- Used by: End user

**Worker Processes:**
- Purpose: Run AI agent tasks in background; isolated from main process
- Location: `src/worker/`, `src/agent/`
- Contains: Agent runners for Gemini, ACP, Codex, OpenClaw, NanoBot
- Depends on: Fork communication channel, AI SDKs
- Used by: `WorkerManage` in main process

**WebServer:**
- Purpose: Remote HTTP + WebSocket access to AI capabilities (headless mode)
- Location: `src/webserver/`
- Contains: Express app, JWT auth, REST routes, WebSocket manager
- Depends on: Main process services (via direct import, shares same Node process)
- Used by: Remote browser clients, IM channel integrations

**Channels Subsystem:**
- Purpose: Multi-platform IM bot integration (Telegram, Lark/Feishu, DingTalk)
- Location: `src/channels/`
- Contains: PluginManager, SessionManager, PairingService, ActionExecutor, platform adapters
- Depends on: WorkerManage, database, ipcBridge (for emitting to renderer)
- Used by: Main process (initialized at startup), AI agents (via ChannelEventBus)

**Extensions:**
- Purpose: Plugin/extension system for loading third-party capabilities
- Location: `src/extensions/`
- Contains: ExtensionRegistry, ExtensionLoader, lifecycle management, sandbox
- Depends on: File system, main process services
- Used by: Main process startup, agent skill loading

**Common:**
- Purpose: Shared types, IPC bridge definitions, utilities accessible from both main and renderer
- Location: `src/common/`
- Contains: `ipcBridge.ts` (all typed IPC channel definitions), storage types, utilities
- Depends on: `@office-ai/platform` bridge primitives
- Used by: All process types

## Data Flow

**User sends a message:**

1. User types in `src/renderer/pages/conversation/` and invokes `ipcBridge.conversation.sendMessage`
2. `window.electronAPI.emit()` in `src/preload.ts` forwards via Electron IPC
3. Main process bridge handler in `src/process/bridge/conversationBridge.ts` receives the call
4. `WorkerManage.buildConversation()` in `src/process/WorkerManage.ts` returns or creates the correct `AgentManager` (Gemini, ACP, Codex, etc.)
5. The agent manager (`src/process/task/GeminiAgentManager.ts` etc.) forwards the message to the forked worker process (`src/worker/gemini.ts`)
6. Worker executes AI call and emits streamed response chunks back to the manager
7. Manager emits via `ipcBridge.conversation.responseStream` → renderer updates UI in real-time
8. Simultaneously, if a Channel session exists, `ChannelEventBus` routes the same chunks to `ChannelMessageService` → platform plugin → IM user

**IPC Bridge Pattern:**
- Bridge channels are defined once in `src/common/ipcBridge.ts` using `bridge.buildProvider` / `bridge.buildEmitter`
- Providers (request-response): `ipcBridge.X.Y.invoke()` from renderer, `ipcBridge.X.Y.provider(fn)` from main
- Emitters (push events): `ipcBridge.X.Y.emit(data)` from main, `ipcBridge.X.Y.on(cb)` from renderer
- The `src/adapter/` directory contains process-specific adapter implementations (`main.ts`, `browser.ts`)

**State Management:**
- No global client-side state library; React Contexts used (`AuthContext`, `ThemeContext`, `ConversationTabsContext`, `PreviewContext`)
- Server state fetched via SWR hooks in renderer
- Persistent state lives in SQLite via `better-sqlite3` accessed exclusively from main process
- Config/preferences use `ConfigStorage` (renderer-accessible) and `ProcessConfig` (main-only)

## Key Abstractions

**AgentManager / BaseAgentManager:**
- Purpose: Manages lifecycle of a single AI conversation worker fork
- Examples: `src/process/task/GeminiAgentManager.ts`, `src/process/task/AcpAgentManager.ts`, `src/process/task/CodexAgentManager.ts`
- Pattern: Extends `ForkTask` from `@/worker/fork/ForkTask`; each type has a matching worker entry in `src/worker/`

**IPC Bridge Channel:**
- Purpose: Typed, bidirectional communication abstraction between renderer and main
- Examples: `src/common/ipcBridge.ts` — `conversation`, `channel`, `cron`, `application`, `model`, `task`, `auth`...
- Pattern: `bridge.buildProvider<ReturnType, ParamsType>(channelName)` or `bridge.buildEmitter<EventType>(channelName)`

**Channel Plugin (BasePlugin):**
- Purpose: Platform-specific IM integration adapter with lifecycle state machine
- Examples: `src/channels/plugins/telegram/TelegramPlugin.ts`, `src/channels/plugins/lark/LarkPlugin.ts`, `src/channels/plugins/dingtalk/DingTalkPlugin.ts`
- Pattern: Extends `BasePlugin`, implements `onInitialize`, `onStart`, `onStop`, `sendMessage`, `editMessage`

**Extension:**
- Purpose: Third-party plugin loaded at runtime
- Examples: `examples/hello-world-extension/`, `examples/e2e-full-extension/`
- Pattern: JSON manifest + entry points; loaded by `ExtensionRegistry` at startup

## Entry Points

**Electron Main Process:**
- Location: `src/index.ts`
- Triggers: Electron app startup
- Responsibilities: Single instance lock, protocol registration, window creation, `initializeProcess()`, WebServer startup, tray management

**Renderer:**
- Location: `src/renderer/index.ts` → `src/renderer/index.html`
- Triggers: BrowserWindow load
- Responsibilities: React root mount, provider wrapping (Auth, Theme, Preview, ConversationTabs), i18n init

**Preload Script:**
- Location: `src/preload.ts`
- Triggers: BrowserWindow creation (runs in isolated context before renderer)
- Responsibilities: Exposes `window.electronAPI` via `contextBridge`; converts tray IPC events to DOM CustomEvents

**Worker Entries:**
- Location: `src/worker/gemini.ts`, `src/worker/acp.ts`, `src/worker/codex.ts`, `src/worker/openclaw-gateway.ts`, `src/worker/nanobot.ts`
- Triggers: `BaseAgentManager` constructor forks the relevant file
- Responsibilities: Runs AI agent logic in isolated Node.js child process

**WebServer:**
- Location: `src/webserver/index.ts` → `startWebServer(port, allowRemote)`
- Triggers: `--webui` CLI flag, or desktop WebUI preferences at startup
- Responsibilities: Express + WebSocket server; JWT auth; REST + WebSocket AI chat API

## Error Handling

**Strategy:** Fail-soft with console logging; no crash on non-critical errors

**Patterns:**
- Main process has top-level `uncaughtException` and `unhandledRejection` handlers that swallow errors in production
- Bridge handlers wrap operations in try/catch; failures are returned as error responses or logged
- Agent workers communicate errors back to manager via fork messaging; managers update conversation status
- Extension and channel initialization failures are caught and logged without blocking app startup
- WebServer uses Express error middleware (`setupErrorHandler` in `src/webserver/setup.ts`)

## Cross-Cutting Concerns

**Logging:** `@office-ai/platform` logger configured in `src/process/initBridge.ts`; main process logs are bridged to renderer DevTools console via `ipcBridge.application.logStream`

**Validation:** Zod used at data boundaries (AI responses, IPC payloads, extension manifests)

**Authentication:** Two separate auth systems — desktop uses `AuthContext` (stored credentials), WebServer uses JWT (`src/webserver/auth/`) with bcrypt-hashed passwords in SQLite

**Internationalization:** `react-i18next` in renderer; separate `i18next` instance in main process (`src/process/i18n/`); 6 locales in `src/renderer/i18n/locales/<lang>/<module>.json`

**Theming:** CSS custom properties + UnoCSS atomic classes; custom CSS injection via `Layout.tsx`; theme stored in `ConfigStorage`

---

*Architecture analysis: 2026-03-17*
