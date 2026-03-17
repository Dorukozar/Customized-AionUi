# Codebase Concerns

**Analysis Date:** 2026-03-17

---

## Tech Debt

**CronStore bypasses database abstraction layer:**
- Issue: `CronStore` uses `@ts-expect-error` on 8 separate lines to access the private `.db` property of the `DatabaseWrapper`, bypassing its public API entirely
- Files: `src/process/services/cron/CronStore.ts` (lines 178, 249, 292, 301, 311, 321, 333, 346)
- Impact: The DatabaseWrapper's encapsulation is meaningless for this module; any internal refactor of DatabaseWrapper will silently break CronStore without a type error
- Fix approach: Expose raw `db` via a protected or package-internal accessor on the DatabaseWrapper, or add cron-specific query methods to the wrapper

**Extension sandbox permissions are informational only — not enforced:**
- Issue: The sandboxWorker runs extension code with full Worker Thread Node.js privileges. The manifest `permissions` field is noted as "informational only and used for UI display purposes"
- Files: `src/extensions/sandboxWorker.ts` (lines 20-25)
- Impact: Any installed extension can access the filesystem, network, or child_process regardless of its declared permissions
- Fix approach: Implement `vm.runInNewContext` with a custom require proxy, or enforce the Node.js `--experimental-permission` flag as noted in the TODO comment

**`always_allow` permission decisions are not persisted (OpenClaw agent):**
- Issue: When a user grants `allow_always` permission for an OpenClaw agent action, the decision is silently dropped; there is no storage
- Files: `src/agent/openclaw/index.ts` (line 259)
- Impact: Users must re-approve every action on every session even after choosing "always allow"
- Fix approach: Implement an approval store (similar to the Gemini agent's existing approval store) and wire it to the `confirmKey === 'allow_always'` branch

**Permission response handler is unimplemented (OpenClaw agent):**
- Issue: The `handlePermissionResponse` method stores a pending permission with a no-op `resolve` callback. The comment says "TODO: handle permission response once the UI returns a user decision"
- Files: `src/agent/openclaw/index.ts` (lines 622-628)
- Impact: Permission requests for OpenClaw are emitted to the UI but responses from the user are never acted upon — the agent effectively never receives a real user decision
- Fix approach: Implement the `resolve` callback to forward the actual `optionId` from the UI response back to the waiting promise

**Markdown-to-Word conversion strips all formatting:**
- Issue: `markdownToWord` splits on newlines and wraps every line in a plain `TextRun`. No heading styles, bold, italic, links, code blocks, or list items are preserved
- Files: `src/process/services/conversionService.ts` (lines 55-56)
- Impact: Exported `.docx` files lose all rich text structure; feature is technically broken for any content beyond plain text
- Fix approach: Use `marked` or `unified` to parse Markdown to an AST and map AST nodes to `docx` paragraph/run types

**MCP agent files use deep relative imports instead of path aliases:**
- Issue: Several MCP agent files use `../../../../common/storage` instead of `@/common/storage`
- Files: `src/process/services/mcpServices/agents/AionuiMcpAgent.ts`, `CodebuddyMcpAgent.ts`, `GeminiMcpAgent.ts`, `IflowMcpAgent.ts`, `QwenMcpAgent.ts`
- Impact: Fragile paths that break silently on directory restructuring; inconsistent with the rest of the codebase
- Fix approach: Replace with `@/common/storage` path alias

**Non-exhaustive union switch statements:**
- Issue: `src/renderer/hooks/useSendBoxDraft.ts` has two switch statements marked with `// TODO import ts-pattern for exhaustive check`, meaning unhandled union branches fail silently at runtime
- Files: `src/renderer/hooks/useSendBoxDraft.ts` (lines 64, 110)
- Impact: Adding new agent types or send-box modes will silently not be handled
- Fix approach: Either add `ts-pattern` and use `match(...).exhaustive()`, or add a `default: exhaustiveCheck(x)` assertion pattern

---

## Known Bugs

**`uncaughtException` handler is empty in production:**
- Symptoms: Any unhandled synchronous exception in the main process is silently swallowed in production builds with no logging or reporting
- Files: `src/index.ts` (lines 201-207)
- Trigger: Any unhandled throw in the main process when `NODE_ENV !== 'development'`
- Workaround: None; errors disappear without trace in packaged builds

**Migration v8 `down` migration does not remove the `source` column:**
- Symptoms: Rolling back migration v8 only drops indexes; the `source` column remains in the table (SQLite limitation acknowledged but not fully worked around)
- Files: `src/process/database/migrations.ts` (lines 274-279)
- Trigger: Any rollback from version 8 to 7
- Workaround: Manual SQLite table reconstruction

---

## Security Considerations

**`dynamic require via workaround` used in 4 separate locations:**
- Risk: Using a dynamic expression to obtain a `require` reference is an antipattern that suppresses static analysis and can be misused by malicious extension code; it also suppresses bundler warnings about dynamic requires
- Files:
  - `src/webserver/routes/apiRoutes.ts` (line 126)
  - `src/extensions/lifecycle.ts` (line 72)
  - `src/extensions/sandboxWorker.ts` (line 206)
  - `src/extensions/resolvers/ChannelPluginResolver.ts` (line 156)
- Current mitigation: Electron contextIsolation is enabled globally; these are main-process only
- Recommendations: Replace with `createRequire(import.meta.url)` (ESM) or `module.createRequire(__filename)` (CJS); both are bundler-safe and semantically correct

**iframe sandbox uses `allow-scripts allow-same-origin` together:**
- Risk: Combining `allow-scripts` with `allow-same-origin` in an iframe effectively nullifies the sandbox — the embedded script can remove the sandbox attribute from its parent iframe
- Files:
  - `src/renderer/components/SettingsModal/contents/ExtensionSettingsTabContent.tsx` (line 134)
  - `src/renderer/pages/settings/ExtensionSettingsPage.tsx` (line 166)
  - `src/renderer/pages/conversation/preview/components/viewers/HTMLViewer.tsx` (line 406)
- Current mitigation: Extension content is served via `aion-asset://` custom protocol, not `file://` or `http://`
- Recommendations: Remove `allow-same-origin` from extension UI iframes; use `postMessage` bridges exclusively for communication

**`dangerouslySetInnerHTML` without HTML sanitization in `MessageTips`:**
- Risk: `displayContent` (the raw non-JSON message content string) is injected directly into the DOM without any sanitization library
- Files: `src/renderer/messages/MessageTips.tsx` (lines 73-75)
- Current mitigation: Content originates from AI agent responses via IPC, not from external user input directly
- Recommendations: Wrap with DOMPurify or a comparable sanitizer before rendering; the risk escalates if agent responses ever include content from untrusted third-party tool calls

**CDP remote debugging port exposed in dev mode by default:**
- Risk: The app opens a remote debugging port (default 9230) in development, which allows any local process to inspect and control the Electron renderer
- Files: `src/utils/configureChromium.ts` (lines 41-255)
- Current mitigation: Disabled in packaged (`app.isPackaged`) builds; port is localhost-only
- Recommendations: Document the opt-in path clearly; ensure CI builds never run with CDP enabled

**Chromium sandbox disabled for root user:**
- Risk: Running as root with `--no-sandbox` removes Chromium's renderer process isolation entirely
- Files: `src/utils/configureChromium.ts` (lines 33-37)
- Current mitigation: Only triggered when `process.getuid() === 0`; documented
- Recommendations: Add a visible warning in the UI or startup log when running as root in production

---

## Performance Bottlenecks

**Scroll sync uses `setTimeout` instead of `requestAnimationFrame`:**
- Problem: The editor/preview scroll synchronization hook uses `setTimeout`-based debouncing, which causes jank during fast scrolling
- Files: `src/renderer/pages/conversation/preview/hooks/useScrollSync.ts` (lines 62-63)
- Cause: Acknowledged in a TODO comment; `setTimeout` does not align with the browser's rendering cycle
- Improvement path: Replace debounce timer with `requestAnimationFrame` plus a flag guard to prevent re-entrancy

**Large React component files with no code-splitting:**
- Problem: Several renderer components exceed 1,000 lines with no dynamic imports
- Files:
  - `src/renderer/pages/conversation/workspace/index.tsx` (1,239 lines)
  - `src/renderer/pages/settings/AssistantManagement.tsx` (1,442 lines)
  - `src/renderer/pages/conversation/gemini/GeminiSendBox.tsx` (1,009 lines)
- Cause: Complex feature pages with state, sub-components, and handlers all co-located
- Improvement path: Extract sub-components into separate files; use `React.lazy` / `Suspense` for infrequently-viewed sections (e.g., settings panels)

**In-memory rate limiter does not scale across processes:**
- Problem: `RateLimitStore` is a `Map` held in the main process memory; it resets on restart and cannot be shared across multiple WebUI server instances
- Files: `src/webserver/middleware/rateLimiter.ts`
- Cause: Intentional choice to avoid external dependencies; noted in the file header
- Improvement path: Acceptable for current single-instance desktop app; would need Redis or SQLite-backed store if WebUI is ever deployed as a standalone server

---

## Fragile Areas

**`window.__websocketReconnect` global mutation:**
- Files: `src/adapter/browser.ts` (line 233), `src/renderer/context/AuthContext.tsx` (lines 148-149)
- Why fragile: A function is attached to `window` as a side-effect in the adapter and consumed via `(window as any).__websocketReconnect()` with a runtime existence check; there is no type contract enforcing the shape
- Safe modification: The `browser.ts` interface declares `__websocketReconnect?: () => void` but the renderer accesses it via `as any`, bypassing the declaration
- Fix approach: Export the reconnect trigger through the existing `ipcBridge` or a typed event emitter rather than window globals

**Agent manager files exceed 900 lines with deeply nested state machines:**
- Files:
  - `src/process/task/AcpAgentManager.ts` (1,119 lines)
  - `src/process/task/GeminiAgentManager.ts` (899 lines)
  - `src/agent/acp/index.ts` (1,500 lines)
- Why fragile: Large stateful classes with interleaved lifecycle, event handling, and error recovery logic are difficult to reason about; a change to connection teardown can silently affect reconnection behavior
- Test coverage: AcpAgentManager and GeminiAgentManager are not listed in `vitest.config.ts` coverage includes

**IPC bridge surface area is very large:**
- Files: `src/common/ipcBridge.ts` (959 lines)
- Why fragile: Nearly 1,000 lines of IPC channel definitions with no layering; adding or renaming a channel requires updating the bridge, preload, and renderer in sync with no compile-time cross-process type enforcement between processes
- Safe modification: Follow existing naming convention; any rename requires grepping all three layers manually

**useEffect cleanup is sparse relative to subscription count:**
- Files: `src/renderer/` (338 `useEffect` calls, only ~15 with cleanup return functions)
- Why fragile: Subscriptions, event listeners, and timers set up in `useEffect` without cleanup functions will accumulate on component unmount, leading to memory leaks and stale callbacks in long-running sessions
- Safe modification: Always return a cleanup function from effects that set up subscriptions or timers

---

## Test Coverage Gaps

**Core agent managers have no unit tests:**
- What is not tested: `AcpAgentManager`, `GeminiAgentManager`, session lifecycle, agent restart/reconnect logic
- Files: `src/process/task/AcpAgentManager.ts`, `src/process/task/GeminiAgentManager.ts`
- Risk: Agent state machine bugs (e.g., double-start, failed reconnect) go undetected until runtime
- Priority: High

**OpenClaw agent is untested:**
- What is not tested: Permission handling, message dispatch, `allow_always` caching (which is also broken per tech debt above)
- Files: `src/agent/openclaw/index.ts`
- Risk: The permission resolution bug described above would be caught by unit tests
- Priority: High

**Coverage thresholds are very low:**
- What is not tested: Coverage is only required on an explicit opt-in file list in `vitest.config.ts`; most of the 629 source files are excluded from coverage measurement entirely. Thresholds are set at 30% statements / 10% branches / 35% functions
- Files: `vitest.config.ts` (lines 52-89)
- Risk: Regressions in untested files are invisible; the low branch threshold (10%) means even covered files can have most conditional paths untested
- Priority: Medium

**Renderer hooks have minimal test coverage:**
- What is not tested: `useSendBoxDraft`, `useScrollSync`, most hooks under `src/renderer/hooks/`
- Files: `src/renderer/hooks/`
- Risk: UI state bugs in draft handling or scroll behavior will not be caught before shipping
- Priority: Medium

**Channel plugins (DingTalk, Lark) have no unit tests:**
- What is not tested: Message formatting, webhook handling, credential encryption/decryption flow
- Files: `src/channels/plugins/dingtalk/DingTalkPlugin.ts` (880 lines), `src/channels/plugins/lark/LarkCards.ts` (831 lines)
- Risk: Formatting regressions in outbound messages are only caught manually
- Priority: Medium

---

## Missing Critical Features

**No error reporting or observability in production:**
- Problem: Both `uncaughtException` and `unhandledRejection` handlers in the main process are no-ops in production builds (empty bodies with a TODO comment)
- Files: `src/index.ts` (lines 201-213)
- Blocks: Any production crash diagnosis; there is no mechanism to detect that users are experiencing errors

**No persistent approval store for OpenClaw permissions:**
- Problem: Unlike the Gemini agent (which has an existing approval store), OpenClaw "always allow" decisions are dropped at agent teardown
- Files: `src/agent/openclaw/index.ts` (line 259)
- Blocks: Practical usability of the OpenClaw agent for power users who do not want to re-approve common tool actions every session

---

*Concerns audit: 2026-03-17*
