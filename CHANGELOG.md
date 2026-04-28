# Changelog

## Changes 04/28/2026 (v0.1.6)

`fix(v0.1.6): clean up highlight API usage and timer safety warnings`

**Commit message**

```text
fix(v0.1.6): clean up highlight API usage and timer safety warnings

- ui(layout): replace deprecated buffer highlight calls in the Wayfinder layout with extmark-based range highlights while preserving pane styling
- preview: guard preview window attachment when the preview pane disappears mid-render
- lsp(async): clarify timer lifecycle and nilability in LSP and async helpers to avoid stale timer warnings
- util: normalize vim.system results and move debounce timers to vim.uv
```

**Fixed**

- **Deprecated layout highlight API**
  - Replaced deprecated buffer highlight calls in the Wayfinder layout renderer with extmark-based range highlights.
  - Preserved the existing visual hierarchy for the facet rail, result list, top bar, and footer hints.

- **Preview window safety**
  - Fixed a case where preview rendering could try to attach a buffer to a preview window that had already been closed.

- **Timer lifecycle warnings**
  - Cleaned up timer handling in the LSP source and async helpers so timer creation and teardown are explicit and safer under static analysis.

**Changed**

- **Async helper result normalization**
  - `vim.system()` results are now normalized before callback delivery instead of mutating the raw result object.

- **Debounce timer backend**
  - Debounce timers now use `vim.uv` consistently.

---

## Changes 04/27/2026 (v0.1.5)

`release(v0.1.5): keep Wayfinder responsive during slow LSP work`

**Commit message**

```text
release(v0.1.5): keep Wayfinder responsive during slow LSP work

- lsp(async): track and cancel stale LSP requests across open, close, refresh, and symbol changes
- lsp(bounds): chunk large LSP response processing and finalize safely on timeout instead of blocking the editor
- lsp(flow): defer expensive LSP facets slightly so the picker opens first and stays responsive while results load
```

**Changed**

- **Async LSP request lifecycle**
  - Wayfinder now tracks in-flight LSP requests per session and cancels or ignores stale work when the picker closes, refreshes, or reopens on a different symbol.
  - Normal open and close paths stay responsive even when LSP-backed sources are still running.

- **Bounded LSP result processing**
  - Large LSP reference and caller payloads are processed in bounded chunks instead of one heavy pass on the main thread.
  - Slow LSP-backed sources now finalize safely on timeout instead of leaving the picker stuck in a loading state.

- **Non-blocking open path**
  - Expensive LSP facets are deferred slightly behind the initial open so the centered picker appears first and remains interactive while results populate.

- **Full UI close on `:q`**
  - Running `:q` from a focused Wayfinder pane now closes the full Wayfinder UI through the normal shutdown path instead of leaving part of the picker behind.
  - This came in via PR #4. Thanks to @joshuamblanch for the contribution.

**Added**

- **Minimal LSP timeout control**
  - Added `limits.refs.timeout_ms` as an optional cap for slow LSP-backed collection in large repositories.

---

## Changes 04/27/2026 (v0.1.4)

`release(v0.1.4): add scope and performance controls for large repos`

**Commit message**

```text
release(v0.1.4): add scope and performance controls for large repos

- scope(config): add project/cwd/package/file_dir scope modes plus package markers and performance presets
- sources(limits): add per-source result caps and timeouts for refs, text matches, tests, and git
- jumps(tagstack): push the origin window position onto the tag stack before normal Wayfinder edit jumps so <C-t> returns cleanly
```

**Added**

- **Scope controls for large repos**
  - Added `scope.mode` with `project`, `cwd`, `package`, and `file_dir` options so Wayfinder can stay focused in large repos and monorepos.
  - Added configurable `package_markers` so `package` scope can stop at the nearest app or module root.

- **Performance presets and source limits**
  - Added `performance = "fast" | "balanced" | "full"` for quick tuning without rewriting the config.
  - Added per-source limits and timeouts for `refs`, `text`, `tests`, and `git` so expensive sources stay responsive.

- **Tag stack integration for edit jumps**
  - Normal Wayfinder edit jumps now push the origin position onto the tag stack so `<C-t>` can return to where the jump started.
  - This came in via PR #2. Thanks to @joshuamblanch for the contribution.

**Changed**

- **Scope-aware result gathering**
  - Text matches, likely tests, and git collection now respect the active Wayfinder scope instead of always searching the full project.
  - LSP results are post-filtered to the active scope where practical, which makes package mode behave better in monorepos.

---

## Changes 04/26/2026 (v0.1.3)

`fix(v0.1.3): Trail remove keybinding conflict and Trail clear action (closes #1)`

**Commit message**

```text
fix(v0.1.3): Trail remove keybinding conflict and Trail clear action (closes #1)

- keys(trail): move details toggle from d to D so dd reliably removes pinned Trail items
- keys(trail): add da to clear the full Trail from inside Wayfinder
- ui(footer): expand the bottom keyhint strip to two lines so Trail actions are easier to discover
```

**Fixed**

- **Trail remove keybinding conflict**
  - Fixed where `dd` would trigger the single-key details toggle instead of removing the selected pinned Trail item.
  - Details now use `D`, so `dd` works reliably for Trail removal.

**Added**

- **Trail clear action**
  - Added `da` inside Wayfinder to clear the full Trail quickly.

**Changed**

- **Footer keyhint layout**
  - Expanded the bottom keyhint strip to two lines so movement, Trail actions, and export controls are easier to scan.

---

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

---

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
