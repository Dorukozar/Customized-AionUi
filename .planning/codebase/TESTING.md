# Testing Patterns

**Analysis Date:** 2026-03-17

## Test Framework

**Runner:**
- Vitest 4 (`^4.0.18`)
- Config: `vitest.config.ts`

**Assertion Library:**
- Vitest built-in (`expect`)
- `@testing-library/jest-dom` extended matchers for DOM tests (via `vitest.dom.setup.ts`)

**Run Commands:**
```bash
bun run test               # Run all tests (node + dom)
bun run test:watch         # Watch mode
bun run test:coverage      # Coverage report (v8 provider)
bun run test:integration   # Integration tests only
bun run test:e2e           # E2E tests via Playwright
```

## Test File Organization

**Location:** Separate `tests/` directory at project root — NOT co-located with source.

**Structure:**
```
tests/
├── unit/                  # Unit tests: functions, hooks, services, components
│   ├── extensions/        # Sub-group for extension system tests
│   ├── *.test.ts          # Node environment (default)
│   ├── *.dom.test.ts      # jsdom environment (React hooks/components)
│   └── *.dom.test.tsx     # jsdom environment (React component rendering)
├── integration/           # Integration tests: i18n, build artifacts, service interactions
├── regression/            # Regression tests: named after the bug/issue they prevent
├── e2e/
│   ├── specs/             # Playwright e2e specs (*. e2e.ts)
│   ├── helpers/           # Shared helper utilities
│   ├── fixtures.ts        # Playwright + Electron app fixture (singleton app lifecycle)
│   └── report/            # Generated HTML reports (gitignored)
├── vitest.setup.ts        # Node environment setup (mocks electronAPI)
└── vitest.dom.setup.ts    # jsdom environment setup (adds DOM matchers + browser mocks)
```

**Naming:**
- Unit/node: `<subjectName>.test.ts` (e.g., `cronService.test.ts`)
- Unit/dom: `<subjectName>.dom.test.ts` or `<subjectName>.dom.test.tsx`
- Integration: `<feature>.test.ts` or `<feature>.integration.test.ts`
- Regression: `<issue_description>.test.ts`
- E2E: `<feature>.e2e.ts`

## Two Test Environments

**Node project** (`vitest.config.ts` → `test.projects[0]`):
- Environment: `node`
- Includes: `tests/unit/**/*.test.ts`, `tests/integration/**/*.test.ts`
- Excludes: `*.dom.test.ts`, `*.dom.test.tsx`
- Setup: `tests/vitest.setup.ts` (mocks `electronAPI` global)

**DOM project** (`vitest.config.ts` → `test.projects[1]`):
- Environment: `jsdom`
- Includes: `tests/unit/**/*.dom.test.ts`, `tests/unit/**/*.dom.test.tsx`
- Setup: `tests/vitest.dom.setup.ts` (adds jest-dom matchers + browser API mocks)

## Test Structure

**Suite organization:**
```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

describe('CronService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('init', () => {
    it('should remove orphan jobs whose conversation no longer exists', async () => {
      // arrange
      // act
      // assert
    });
  });
});
```

**DOM component tests:**
```typescript
import React from 'react';
import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

describe('SlashCommandMenu', () => {
  it('renders loading text from props and exposes aria-busy', () => {
    render(<SlashCommandMenu ... />);
    expect(screen.getByText('...')).toBeInTheDocument();
    expect(screen.getByRole('listbox')).toHaveAttribute('aria-busy', 'true');
  });
});
```

**Hook tests with `renderHook`:**
```typescript
import { renderHook, act } from '@testing-library/react';

const { result, rerender } = renderHook(({ messages, itemCount }) => useAutoScroll({ messages, itemCount }), {
  initialProps: { messages: initialMessages, itemCount: 2 },
});

rerender({ messages: newMessages, itemCount: 3 });

await act(async () => {
  vi.runAllTimers();
});
```

**Patterns:**
- `beforeEach(() => { vi.clearAllMocks(); })` — standard cleanup in unit tests
- `afterEach(() => { vi.useRealTimers(); vi.clearAllMocks(); })` — timer-based tests
- `vi.useFakeTimers()` / `vi.runAllTimers()` in `beforeEach`/`afterEach` for async timer tests
- Arrange-act-assert structure within each `it` block

## Mocking

**Framework:** Vitest `vi` object (no separate mock library)

**Module mocks — top-level `vi.mock()`:**
```typescript
vi.mock('electron', () => ({
  powerSaveBlocker: {
    start: vi.fn(),
    stop: vi.fn(),
  },
  app: {
    getPath: vi.fn(() => '/test/path'),
  },
}));

vi.mock('../../src/process/services/cron/CronStore', () => ({
  cronStore: {
    listAll: vi.fn(() => []),
    insert: vi.fn(),
    // ...
  },
}));
```

**Dynamic mocks (`vi.doMock`) for tests requiring `vi.resetModules()`:**
```typescript
beforeEach(async () => {
  vi.resetModules();
  vi.clearAllMocks();
  vi.doMock('electron', () => ({ app: { ... } }));
  // ... more doMocks
});
```

**Asserting mock calls:**
```typescript
vi.mocked(cronStore.listAll).mockReturnValue([orphanJob]);
vi.mocked(cronStore.getById).mockReturnValueOnce(existingJob).mockReturnValue(updatedJob);

expect(cronStore.delete).toHaveBeenCalledWith(orphanJob.id);
expect(ipcBridge.cron.onJobRemoved.emit).toHaveBeenCalledWith({ jobId });
expect(cronStore.delete).not.toHaveBeenCalled();
```

**What to mock:**
- `electron` — always mock in all node-environment tests (not available outside Electron)
- IPC bridges (`ipcBridge`) — mock with `vi.fn()` stubs per test file
- Database layer (`getDatabase`) — mock return values
- File system when testing logic, not filesystem behavior (use real fs for integration tests)

**What NOT to mock:**
- Real filesystem in `tests/integration/` and `tests/unit/extensions/` — these use `fs.mkdtempSync` sandboxes
- The subject under test itself

## Fixtures and Factories

**In-test factory functions (preferred over shared fixtures):**
```typescript
const createMockVirtuosoHandle = () => ({
  scrollToIndex: vi.fn(),
  scrollTo: vi.fn(),
  scrollBy: vi.fn(),
  getState: vi.fn(),
  autoscrollToBottom: vi.fn(),
});
```

**Inline data objects for test scenarios:**
```typescript
const orphanJob = {
  id: 'cron_orphan',
  name: 'Orphan Job',
  enabled: true,
  schedule: { kind: 'every', everyMs: 60000, description: 'Every minute' } as any,
  // ...
};
```

**Filesystem sandbox pattern (integration/extension tests):**
```typescript
const tempRoots: string[] = [];

function createTempDir(prefix: string): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  tempRoots.push(dir);
  return dir;
}

afterEach(() => {
  for (const root of tempRoots.splice(0, tempRoots.length)) {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
```

**Location:** No shared `__fixtures__` folder. Factories and data are defined within test files or in `tests/e2e/helpers/`.

## Coverage

**Provider:** v8 (`@vitest/coverage-v8`)

**Reports:** `text`, `text-summary`, `html` → `./coverage/`

**Thresholds (enforced):**
- Statements: 30%
- Branches: 10%
- Functions: 35%
- Lines: 30%

**Explicitly included files** (must be manually added to `vitest.config.ts → coverage.include` when adding new features):
- Process/bridge services: `src/process/bridge/services/`, `src/process/bridge/*Bridge.ts`
- ACP layer: `src/agent/acp/`
- Extension system: `src/extensions/`
- Renderer utils: `src/renderer/messages/`, `src/renderer/utils/emitter.ts`
- Renderer components with tests: added individually

**Adding new files to coverage:**
```typescript
// vitest.config.ts → coverage.include array
'src/process/services/myNewService.ts',
```

**View coverage:**
```bash
bun run test:coverage
open coverage/index.html
```

## Test Types

**Unit Tests (`tests/unit/`):**
- Scope: individual functions, utilities, services (node), React hooks and components (dom)
- Use `vi.mock()` extensively to isolate the subject
- Import subjects directly from `src/`

**Integration Tests (`tests/integration/`):**
- Scope: i18n file structure, build artifact integrity, service interactions
- Use real filesystem and real module imports
- No mocking of core subjects; test actual behavior end-to-end within Node

**Regression Tests (`tests/regression/`):**
- Named after the bug/issue they prevent re-occurrence of
- Single-purpose: verify a specific previously-broken scenario

**E2E Tests (`tests/e2e/`):**
- Framework: Playwright + `@playwright/test`
- Config: `playwright.config.ts`
- Electron app launched via custom fixture (`tests/e2e/fixtures.ts`)
- Workers: 1 (singleton app shared across all specs in a worker)
- Timeout: 60s per test, 10s for `expect` assertions
- Retries: 1 in CI, 0 locally
- Two modes: packaged (CI default, `E2E_PACKAGED=1`) and dev (local default, `E2E_DEV=1`)

## E2E Patterns

**Fixture import (not `@playwright/test` directly):**
```typescript
import { test, expect } from '../fixtures';
import { createErrorCollector, waitForSettle } from '../helpers';
```

**Spec structure:**
```typescript
test.describe('App Launch', () => {
  test('window opens and has a title', async ({ page }) => {
    const title = await page.title();
    expect(title).toBeTruthy();
  });
});
```

**Helper utilities:** Shared test helpers live in `tests/e2e/helpers/` (e.g., `createErrorCollector`, `waitForSettle`).

**Screenshot on failure:** Automatically attached to test results by the custom `page` fixture when a test fails.

## Setup Files

**`tests/vitest.setup.ts`** — node environment:
- Declares `electronAPI` global type
- Mocks `global.electronAPI` with no-op stubs for `emit`, `on`, `windowControls`

**`tests/vitest.dom.setup.ts`** — jsdom environment:
- Imports `@testing-library/jest-dom/vitest` for `toBeInTheDocument()` etc.
- Same `electronAPI` mock as node setup
- Mocks `ResizeObserver` (required for `react-virtuoso`)
- Mocks `IntersectionObserver`
- Mocks `requestAnimationFrame` / `cancelAnimationFrame` via `setTimeout`
- Mocks `Element.prototype.scrollTo` and `scrollIntoView`

## Common Patterns

**Async testing:**
```typescript
it('should scroll on user message', async () => {
  const { result, rerender } = renderHook(...);

  rerender({ messages: newMessages, itemCount: 3 });

  await act(async () => {
    vi.runAllTimers();
  });

  expect(mockVirtuosoHandle.scrollToIndex).toHaveBeenCalledWith(
    expect.objectContaining({ index: 'LAST', behavior: 'auto' })
  );
});
```

**Accessing private fields in tests:**
```typescript
// Pattern used when testing internal state that has no public API
(cronService as any).initialized = false;
```

**Partial matcher:**
```typescript
expect(fn).toHaveBeenCalledWith(expect.objectContaining({ index: 'LAST' }));
```

**Error testing:**
```typescript
it('should handle error', async () => {
  vi.mocked(someService.method).mockRejectedValue(new Error('Network error'));
  // ... invoke subject
  expect(result.current.error).toBe('Network error');
});
```

**Negative assertions:**
```typescript
expect(cronStore.delete).not.toHaveBeenCalled();
expect(mockVirtuosoHandle.scrollToIndex).not.toHaveBeenCalled();
```

---

*Testing analysis: 2026-03-17*
