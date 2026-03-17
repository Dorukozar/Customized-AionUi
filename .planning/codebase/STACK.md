# Technology Stack

**Analysis Date:** 2026-03-17

## Languages

**Primary:**
- TypeScript 5.8 (strict mode) - All source code across main process, renderer, and workers
- TSX - React components in `src/renderer/`

**Secondary:**
- JavaScript - Build scripts in `scripts/`, config files

## Runtime

**Environment:**
- Node.js >=22 <25 (enforced in `package.json` engines field)
- Electron 37 — desktop app host; main process runs Node.js, renderer runs Chromium

**Package Manager:**
- Bun (all scripts use `bun run ...`)
- Lockfile: `bun.lock` present

## Frameworks

**Core:**
- Electron 37 (`electron@^37.3.1`) — multi-process desktop shell
- React 19 (`react@^19.1.0`) — renderer UI layer
- React Router DOM 7 (`react-router-dom@^7.8.0`) — client-side routing in renderer

**UI Component Library:**
- Arco Design 2 (`@arco-design/web-react@^2.66.1`) — primary component library
- Icon Park (`@icon-park/react@^1.4.2`) — icon set, wrapped via custom `IconParkHOC`

**Styling:**
- UnoCSS 66 (`unocss@^66.3.3`) — atomic CSS with custom theme tokens mapped to CSS variables
- CSS Modules — component-specific styles via `*.module.css`
- Config: `uno.config.ts` (presets: `presetMini`, `presetExtra`, `presetWind3`)

**Testing:**
- Vitest 4 (`vitest@^4.0.18`) — unit/integration tests
- Playwright (`@playwright/test@^1.58.2`) — E2E tests
- Config: `vitest.config.ts`, `playwright.config.ts`

**Build/Dev:**
- electron-vite 5 (`electron-vite@^5.0.0`) — unified build tool for all three Electron processes
- Vite 6 (`vite@^6.4.1`) — underlying bundler
- electron-builder 26 (`electron-builder@^26.6.0`) — packaging and distribution
- Config: `electron.vite.config.ts`, `electron-builder.yml`

**Scheduling:**
- Croner 9 (`croner@^9.1.0`) — cron job scheduling in `src/process/services/cron/`

**WebServer (WebUI mode):**
- Express 5 (`express@^5.1.0`) — embedded HTTP server in `src/webserver/`
- express-rate-limit 7 — API rate limiting
- ws 8 (`ws@^8.18.3`) — WebSocket server in `src/webserver/websocket/`
- cors 2 — CORS middleware
- cookie-parser 1 — cookie parsing
- tiny-csrf 1 — CSRF protection

## Key Dependencies

**AI Agent SDKs:**
- `@office-ai/aioncli-core@^0.30.0` — ACP (AI Command Protocol) core; wraps Claude Code, iFlow, and similar backends
- `@office-ai/platform@^0.3.16` — platform utilities including `storage` (persisted key-value store)
- `@anthropic-ai/sdk@^0.71.2` — Anthropic Claude direct API
- `openai@^5.12.2` — OpenAI API and OpenAI-compatible endpoints (used for most custom providers)
- `@google/genai@^1.16.0` — Google Gemini API
- `@aws-sdk/client-bedrock@^3.987.0` — AWS Bedrock
- `@modelcontextprotocol/sdk@^1.20.0` — MCP (Model Context Protocol) tool server integration

**Database:**
- `better-sqlite3@^12.4.1` — synchronous SQLite, native addon; unpacked from asar

**Auth:**
- `jsonwebtoken@^9.0.2` — JWT generation and verification
- `bcryptjs@^2.4.3` — password hashing (12 salt rounds)

**Document Parsing:**
- `mammoth@^1.11.0` — Word (.docx) import
- `officeparser@^5.2.2` — Office file parsing
- `xlsx-republish@^0.20.3` — Excel parsing
- `html-to-text@^9.0.5` — HTML → text
- `turndown@^7.2.2` — HTML → Markdown
- `docx@^9.5.1` — Word document generation

**Code Editing:**
- `@monaco-editor/react@^4.7.0` — Monaco editor (VS Code engine) in renderer
- `@uiw/react-codemirror@^4.25.2` — CodeMirror editor in renderer
- `web-tree-sitter@^0.25.10` — Tree-sitter WASM for syntax parsing

**Markdown/Math:**
- `react-markdown@^10.1.0` — markdown rendering
- `remark-gfm`, `remark-math`, `rehype-katex`, `katex@^0.16.22` — GFM and math rendering
- `react-syntax-highlighter@^16.1.0` — code block syntax highlighting

**Messaging Channels:**
- `grammy@^1.39.3` — Telegram Bot API
- `@larksuiteoapi/node-sdk@^1.58.0` — Lark/Feishu API
- `dingtalk-stream@^2.1.4` — DingTalk streaming API

**Utilities:**
- `zod@^3.25.76` — runtime schema validation at data boundaries
- `swr@^2.3.6` — data fetching/caching in renderer
- `eventemitter3@^5.0.1` — event emitter
- `semver@^7.7.2` — version comparison for auto-updater
- `electron-updater@^6.6.2` — auto-update via GitHub Releases
- `electron-log@^5.4.3` — logging to file
- `sharp@^0.34.3` — image processing (native addon)
- `i18next@^23.7.16` + `react-i18next@^14.0.5` — internationalization
- `@dnd-kit/core`, `@dnd-kit/sortable` — drag-and-drop in renderer
- `@floating-ui/react@^0.27.16` — floating UI positioning
- `react-virtuoso@^4.18.1` — virtualized lists

## Configuration

**Environment:**
- No `.env` file present; secrets are injected at runtime or stored encrypted in SQLite
- `JWT_SECRET` env var optionally overrides the DB-stored JWT secret (see `src/webserver/auth/service/AuthService.ts`)
- `ACP_PERF=1`, `PERF_MONITOR=1` enable performance debug mode

**Build:**
- `electron.vite.config.ts` — defines main/preload/renderer builds with path aliases
- `electron-builder.yml` — packaging config for macOS (dmg, zip), Windows (nsis, zip), Linux (deb)
- `tsconfig.json` — TypeScript config (`target: ES6`, `moduleResolution: bundler`)
- `uno.config.ts` — UnoCSS with semantic color tokens

**Path Aliases:**
- `@/*` → `src/`
- `@process/*` → `src/process/`
- `@renderer/*` → `src/renderer/`
- `@worker/*` → `src/worker/`
- `@common/*` → `src/common/` (in vitest config)

**Linting/Formatting:**
- ESLint 8 — `.ts`, `.tsx` files; runs via `bun run lint`
- Prettier 3 — all source files; enforced in CI via format check
- Husky 9 + lint-staged — pre-commit hooks run `eslint --fix` and `prettier --write`

## Platform Requirements

**Development:**
- Node.js >=22 <25, Bun
- macOS (primary), Windows, Linux supported

**Production:**
- macOS: signed dmg/zip, hardened runtime, notarized via `@electron/notarize`
- Windows: NSIS installer + zip
- Linux: deb (x64, arm64)
- Auto-updates distributed via GitHub Releases (owner: `iOfficeAI`, repo: `AionUi`)

---

*Stack analysis: 2026-03-17*
