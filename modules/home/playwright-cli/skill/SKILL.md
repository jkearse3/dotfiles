---
name: playwright-cli
description:
  Use when browser automation, UI inspection, screenshots, snapshots, web
  interaction, Playwright test debugging, or browser session control is needed
  through the `playwright-cli` command.
---

# Playwright CLI

Use `playwright-cli` for local browser interaction from the terminal. It is
useful for inspecting pages, getting accessible snapshots, clicking or typing
through UI flows, capturing screenshots, debugging browser state, and gathering
console or network evidence.

Prefer this CLI when a browser is needed and the task does not explicitly
require another browser interface. Do not start an MCP server just to perform
ordinary browser inspection or interaction.

## Setup

- Start by using `playwright-cli` from `PATH`. If it is missing, report that the
  CLI is unavailable instead of installing packages globally.
- Do not run `playwright-cli install --skills` as part of normal use; this skill
  is already installed by the active agent environment.
- Do not run `playwright-cli install-browser` unless the browser is missing and
  the user wants the CLI to manage browser downloads. Some environments provide
  browsers externally, such as through Nix or another package manager.

## Workflow

1. Open a page with `playwright-cli open <url>`.
2. Run `playwright-cli snapshot` to get element refs and page structure.
3. Interact with refs from the snapshot, such as `playwright-cli click e15` or
   `playwright-cli fill e4 "text"`.
4. Re-run `playwright-cli snapshot` after meaningful interactions.
5. Use focused diagnostic commands when needed: `console`, `network`, `eval`,
   `screenshot`, `tracing-start`, and `tracing-stop`.
6. Close sessions with `playwright-cli close` or `playwright-cli close-all` when
   finished.

## Commands

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli click e3
playwright-cli fill e5 "user@example.com"
playwright-cli press Enter
playwright-cli console
playwright-cli network
playwright-cli screenshot --filename=page.png
playwright-cli close
```

Use named sessions when parallel or persistent browser work would otherwise
collide:

```bash
playwright-cli -s=checkout open https://example.com
playwright-cli -s=checkout snapshot
playwright-cli -s=checkout close
```

## Guidance

- Prefer snapshots over screenshots for understanding page structure and finding
  stable refs.
- Use screenshots when visual layout, styling, or pixel evidence matters.
- Use `eval` for targeted browser-side facts that snapshots do not expose, such
  as attributes, computed styles, or local JavaScript state.
- Use `console` and `network` when diagnosing frontend errors, failed requests,
  or missing data.
- Use `state-save` and `state-load` only when preserving authentication or
  browser storage is part of the task.
- Use `close-all` for cleanup when stale sessions could affect later work.

## Safety

- Do not enter real credentials, payment data, personal data, or secrets unless
  the user explicitly instructs you to do so for a trusted environment.
- Avoid destructive actions in a browser, such as deleting production data or
  submitting real orders, unless the user explicitly asks and the target
  environment is confirmed safe.
- Keep generated screenshots, snapshots, videos, traces, and storage state out
  of commits unless the user explicitly wants them versioned.
