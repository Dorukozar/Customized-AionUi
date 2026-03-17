# Coding Conventions

**Analysis Date:** 2026-03-17

## Naming Patterns

**Files:**
- React components: PascalCase (`ThemeSwitcher.tsx`, `AppLoader.tsx`, `SlashCommandMenu.tsx`)
- Hooks: camelCase with `use` prefix (`useAutoScroll.ts`, `useAgentReadinessCheck.ts`)
- Services: PascalCase for classes (`CronService.ts`, `AutoUpdaterService.ts`), camelCase for singleton exports
- Utilities: camelCase (`configureChromium.ts`, `conversionService.ts`)
- Constants: UPPER_SNAKE_CASE
- Unused parameters/variables: prefix with `_`

**Directories:**
- Feature directories: camelCase (`hooks/`, `services/`, `messages/`)
- Component directories: PascalCase when named after a component (`SettingsModal/`)

**Classes:**
- PascalCase (`CronService`, `AutoUpdaterService`, `ExtensionLoader`)
- Class instances / singleton exports: camelCase (`cronService`, `autoUpdaterService`)

**Types and Interfaces:**
- Use `type` over `interface` (ESLint enforces `@typescript-eslint/consistent-type-imports`)
- Props type: `${ComponentName}Props` pattern (e.g., `SlashCommandMenuProps`)
- State types: descriptive suffixes (`AgentReadinessState`, `AutoUpdateStatus`)
- Callback types: verb-noun pattern (`StatusBroadcastCallback`)

**React Hooks:**
- Functions: `use*` prefix (`useThemeContext`, `useAutoScroll`)
- Event handlers: `on*` prefix (`onAgentReady`, `onSelectItem`, `onHoverItem`)

## Code Style

**Formatting Tool:** Prettier 3 (`/.prettierrc.json`)

**Key settings:**
- Single quotes (`singleQuote: true`, `jsxSingleQuote: true`)
- Semicolons required (`semi: true`)
- 2-space indentation (`tabWidth: 2`, `useTabs: false`)
- Print width: 120 characters (`printWidth: 120`)
- Trailing commas: ES5 style (`trailingComma: "es5"`)
- Arrow function parentheses: always (`arrowParens: "always"`)
- Bracket spacing in objects: yes (`bracketSpacing: true`)
- JSX closing bracket: new line (`bracketSameLine: false`)
- Line endings: LF (`endOfLine: "lf"`)

**Linting Tool:** ESLint 8 (`/.eslintrc.json`)

**Key rules:**
- `@typescript-eslint/consistent-type-imports` — prefer `import type` for type-only imports (error)
- `@typescript-eslint/no-floating-promises` — all promises must be awaited or void-cast (error)
- `@typescript-eslint/await-thenable` — only await actual thenables (error)
- `@typescript-eslint/no-unused-vars` — warn, args/vars prefixed with `_` are exempt
- `max-len` — 120 chars, ignores URLs, strings, template literals (warning)
- `@typescript-eslint/no-explicit-any` — warn (not error)
- `prettier/prettier` — Prettier violations are ESLint errors

**Void-casting unhandled promises:**
```typescript
// Pattern used throughout codebase for fire-and-forget promises in event handlers
void setTheme(option.value);
void performFullCheck();
```

## Import Organization

**Order (enforced by `eslint-plugin-import`):**
1. External packages (`react`, `electron`, third-party libs)
2. Internal path aliases (`@/`, `@process/`, `@renderer/`, `@worker/`, `@mcp/`)
3. Relative imports (`../../src/...`, `./CronStore`)

**Path Aliases** (defined in `vitest.config.ts` and `tsconfig.json`):
- `@/` → `src/`
- `@process/` → `src/process/`
- `@renderer/` → `src/renderer/`
- `@worker/` → `src/worker/`
- `@mcp/` → `src/common/`
- `@mcp/models/` → `src/common/models/`
- `@mcp/types/` → `src/common/`

**Type-only imports:** Use `import type` for type imports:
```typescript
import type { ProgressInfo, UpdateInfo } from 'electron-updater';
import type { TMessage, IMessageText } from '../../src/common/chatLib';
```

## Error Handling

**Async/await pattern:**
```typescript
try {
  const result = await ipcBridge.acpConversation.checkAgentHealth.invoke({ backend });
  if (result.success && result.data?.available) {
    // handle success
  } else {
    // handle logical failure with result.msg
  }
} catch (error) {
  const message = error instanceof Error ? error.message : 'Unknown error';
  // update state or log
}
```

**Error type narrowing:** Always use `error instanceof Error` before accessing `.message`:
```typescript
error: error instanceof Error ? error.message : 'Unknown error'
```

**IPC result pattern:** Bridge calls return `{ success: boolean; data?: T; msg?: string }` — always check `result.success` before using `result.data`.

**Floating promise rule:** Either `await` or `void`-cast all promises. Non-awaited async calls in event handlers use `void`:
```typescript
onClick={() => { void someAsyncFn(); }}
useEffect(() => { void performFullCheck(); }, []);
```

## Logging

**Main process:** `electron-log` (`import log from 'electron-log'`)

**Renderer/services:** `console.error` for caught exceptions in catch blocks, `console.log` with `[E2E]` prefix in test fixtures.

**Pattern:**
```typescript
// Main process service
autoUpdater.logger = log;

// Catch blocks in renderer hooks
console.error('Failed to find alternatives:', error);
```

## Comments

**File header:** Apache-2.0 SPDX license header on all source files:
```typescript
/**
 * @license
 * Copyright 2025 AionUi (aionui.com)
 * SPDX-License-Identifier: Apache-2.0
 */
```

**JSDoc for exported functions and classes:**
```typescript
/**
 * Hook to check if the current agent is ready to use before sending messages.
 */
export function useAgentReadinessCheck(options: UseAgentReadinessCheckOptions) {
```

**Inline comments:** English. Bilingual (Chinese + English) comments appear in older or community-contributed files but new code should use English only.

**ESLint disable:** Use line-level disable with specific rule name:
```typescript
// eslint-disable-next-line @typescript-eslint/no-explicit-any
```

## Function Design

**Size:** Functions kept focused; long async functions use extracted `useCallback` helpers in hooks.

**Parameters:** Options objects for hooks with multiple parameters:
```typescript
type UseAgentReadinessCheckOptions = {
  backend?: AcpBackendAll;
  conversationType: 'gemini' | 'acp' | 'codex';
  autoCheck?: boolean;
  onAgentReady?: (agent: AgentCheckResult) => void;
};
```

**Return values:** Hooks return flat objects spreading state plus named functions:
```typescript
return {
  ...state,
  checkCurrentAgent,
  findAlternatives,
  performFullCheck,
  reset,
};
```

## Module Design

**Exports:** Named exports preferred. Default exports used for React components and some services.

**Barrel files:** Used for component libraries and i18n locales.
- `src/renderer/components/base/index.ts` — re-exports all base UI components
- `src/renderer/i18n/locales/<lang>/index.ts` — re-exports locale modules

**Class singletons:** Services implemented as classes, exported as singleton instances:
```typescript
class CronService { ... }
export const cronService = new CronService();
```

## React Patterns

**Components:** Functional components only. Arrow function style:
```typescript
export const ThemeSwitcher = () => { ... };
```

**State updates:** Always use functional updater form when new state depends on previous:
```typescript
setState((prev) => ({ ...prev, isChecking: false }));
```

**`useCallback`:** Used for all async functions defined inside hooks to stabilize references for `useEffect` deps.

**`useEffect` + async:** Wrap async logic and void-cast inside effect:
```typescript
useEffect(() => {
  if (autoCheck) {
    void performFullCheck();
  }
}, [autoCheck, performFullCheck]);
```

## Internationalization

All user-facing strings must use `useTranslation` hook — never hardcode strings in components:
```typescript
const { t } = useTranslation();
<button aria-label={t('settings.theme')}>
```

Translation files: `src/renderer/i18n/locales/<lang>/<module>.json`
Reference language: `en-US`. All 6 locales (`en-US`, `zh-CN`, `zh-TW`, `ja-JP`, `ko-KR`, `tr-TR`) must be updated together.

Validation after adding keys:
```bash
node scripts/check-i18n.js
bun run i18n:types
```

---

*Convention analysis: 2026-03-17*
