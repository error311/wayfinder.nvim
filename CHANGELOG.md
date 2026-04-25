# Changelog

## Changes 04/25/2026 (v0.1.2)

`release(v0.1.2): quickfix export, Trail traversal, TrailShow, and focus polish`

**Commit message**

```text
release(v0.1.2): quickfix export, Trail traversal, TrailShow, and focus polish

- trail(quickfix): export the current facet or Trail to quickfix with readable file, line, column, and summary text
- trail(commands): add Trail next, previous, and open commands for navigation outside the Wayfinder UI
- trail(show): add WayfinderTrailShow and a TrailShow mapping to open Wayfinder directly on the Trail facet
```

**Added**

- **Quickfix export for the current facet**
  - Added `:WayfinderExportQuickfix` to export the current visible facet in its current order, including filtered `All` results.
  - Added in-UI quickfix export so the active facet can be pushed into quickfix without leaving Wayfinder.

- **Trail quickfix export**
  - Added `:WayfinderExportTrailQuickfix` to export Trail items to quickfix in Trail order.

- **Trail traversal outside the UI**
  - Added `:WayfinderTrailNext`, `:WayfinderTrailPrev`, and `:WayfinderTrailOpen` so Trail can be used during normal editing without reopening Wayfinder.
  - Added `<Plug>(WayfinderTrailNext)`, `<Plug>(WayfinderTrailPrev)`, and `<Plug>(WayfinderTrailOpen)` for optional user mappings.

- **Trail UI shortcut**
  - Added `:WayfinderTrailShow` and `<Plug>(WayfinderTrailShow)` to open Wayfinder directly on the Trail facet without changing the meaning of `TrailOpen`.

**Changed**

- **Trail navigation safety**
  - Trail traversal now skips invalid or deleted entries instead of breaking navigation flow.

- **Wayfinder focus stability**
  - Fixed a case where Wayfinder could leave input on the buffer behind the popup instead of keeping focus in the active Wayfinder pane.

## Changes 04/24/2026 (v0.1.1)

`feat(navigation): auto-advance empty calls, add reverse facet cycling, and wrap results`

**Commit message**

```text
feat(navigation): auto-advance empty calls, add reverse facet cycling, and wrap results

- navigation(symbol): switch to Refs on open when Calls is empty but Refs already has useful results
- navigation(facets): add <S-Tab> to move backward through facets
- navigation(results): wrap middle-pane movement so next/prev loops across the result list
```

**Changed**

- **Smarter initial facet selection**
  - Wayfinder now skips an empty `Calls` view on symbol-open when `Refs` already has useful results, so the first facet is less likely to feel dead.

- **Reverse facet navigation**
  - Added `<S-Tab>` to move backward through facets, alongside existing forward facet navigation with `<Tab>`.

- **Wrapped result movement**
  - The middle results pane now wraps at the ends, so moving down from the last result returns to the first, and moving up from the first returns to the last.
