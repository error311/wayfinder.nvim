# Changelog

## Changes 05/02/2026 (v0.2.1)

`fix(v0.2.1): polish saved Trail status and preview context`

**Commit message**

```text
fix(v0.2.1): polish saved Trail status and preview context

- ui(topbar): show saved Trail counts in the existing Trail status area
- health: report saved Trail storage root/file details and current-project saved counts
- preview(header): show clearer project-relative file context with line ranges in the preview header
- layout(size): make narrow-editor fallback warnings more specific about the space the 3-pane layout needs
```

**Changed**

- **Saved Trail count in the top bar**
  - The existing Trail status area now includes the current project's saved Trail count when it is relevant.
  - Examples include:
    - `Trail (2 saved)`
    - `Trail (2 saved) • unsaved`
    - `Trail (3 saved): auth bug`
    - `Trail (3 saved): auth bug • modified`

- **Preview header context**
  - The preview header now keeps project-relative file context visible while also showing the selected line or line range.
  - Git previews can show a short commit hash in that same header instead of using a separate label row.

- **Healthcheck Trail diagnostics**
  - `:checkhealth wayfinder` now reports the saved Trail storage root, the current project's saved Trail storage file, and the saved Trail count for the current project.

- **Cleaner narrow-window fallback**
  - When the editor is too small for Wayfinder's centered 3-pane layout, the warning now includes an approximate minimum editor size instead of only saying that the window is too small.

- **Facet selection memory**
  - While Wayfinder stays open, moving away from a facet and coming back now restores the last selected item for that facet when it still exists.
  - A fresh `:Wayfinder` open still starts clean at the top as before.

---

## Changes 05/02/2026 (v0.2.0)

`release(v0.2.0): add persistent named Trails per project`

**Commit message**

```text
release(v0.2.0): add persistent named Trails per project

- trail(save): add save/save-as/load/rename/delete support for named Trails scoped to the current project
- trail(ui): add saved/unsaved Trail state in the top bar and an in-picker S Trail menu
- trail(store): persist Trail data under stdpath("state") without changing normal unsaved Trail behavior
```

**Added**

- **Persistent named Trails per project**
  - Added explicit save, save-as, load, rename, and delete support for named Trails scoped to the current project.
  - Saved Trails live under Neovim state instead of inside the repo.
  - If you never save a Trail, ordinary Trail behavior stays the same.

- **Trail persistence commands**
  - Added `:WayfinderTrailSave`
  - Added `:WayfinderTrailSaveAs`
  - Added `:WayfinderTrailLoad`
  - Added `:WayfinderTrailDelete`
  - Added `:WayfinderTrailRename`

- **In-picker Trail menu**
  - Added `S` inside Wayfinder to open a small Trail menu for save/load/rename/delete actions without introducing a second management UI.

- **Saved Trail cycling**
  - Added `[` and `]` inside Wayfinder to cycle through saved Trails for the current project without reopening the Trail menu.

**Changed**

- **Top bar Trail state**
  - The existing Trail status area now reflects saved and unsaved working Trail state.
  - Examples include:
    - `Trail • unsaved • 3 items`
    - `Trail: auth bug • 3 items`
    - `Trail: auth bug • modified`

- **Explicit persistence semantics**
  - Trail persistence is opt-in by action, not automatic.
  - Pinning items does not auto-save them.
  - Opening Wayfinder does not auto-restore a saved Trail in this first pass.

- **Persistence flow polish**
  - Save/load/rename/delete actions now suspend and restore the current Wayfinder session cleanly around `vim.ui.select` and `vim.ui.input` prompts so prompt UIs do not appear behind the picker.

- **Persistence storage and attachment safety**
  - Saved Trail attachment is now scoped to the current project, so `Save Trail` only reuses an active saved name inside the same repo.
  - The persisted `trails` JSON shape now stays stable even when deleting the last saved Trail.

- **Test harness organization**
  - Split the growing headless test harness into shared support plus grouped Trail, persistence, UI, filter, and source suites while keeping the same coverage.

---

## Changes 05/01/2026 (v0.1.10)

`release(v0.1.10): add compact match reasons for weaker result sources`

**Commit message**

```text
release(v0.1.10): add compact match reasons for weaker result sources

- refs(text): show a small plain-text fallback reason for grep-backed Text Matches
- tests(heuristics): show a concise why-this-matched reason for likely-test results
- git(selection): show a small file-touch reason for the selected Git item while keeping commit metadata in details
```

**Changed**

- **Clearer weak-source trust hints**
  - Text Matches, likely Tests, and Git selections can now surface a concise top-bar reason explaining why the current item showed up.
  - This keeps weaker sources more trustworthy without cluttering the existing 2-line row model.

- **Examples of selection reasons**
  - Text Matches use a plain-text fallback reason.
  - Test matches can surface filename or symbol-text matching.
  - Git selections explain that the commit touched the current file.

- **Filter matching includes reasons**
  - The local `/` filter now matches against these row reasons too, so filtering stays consistent with what the list shows.

- **More useful health output**
  - `:checkhealth wayfinder` now reports `ripgrep`, `git`, current-buffer LSP clients, resolved scope, and the active `performance` / `scope.mode` config instead of only basic load status.

---

## Changes 04/30/2026 (v0.1.9)

`fix(v0.1.9): harden layout borders and narrow-editor opens`

**Commit message**

```text
fix(v0.1.9): harden layout borders and narrow-editor opens

- ui(border): default inner pane floats to border = "none" so global winborder settings do not break the 3-pane layout
- layout(size): detect editors that are too small for the centered 3-pane UI and abort cleanly instead of opening invalid pane widths
- tests(layout): add a regression test for the narrow-editor path so small windows warn and exit without leaving a stale Wayfinder session
```

**Fixed**

- **Inner pane border inheritance**
  - Inner Wayfinder panes now default to `border = "none"` unless they explicitly request a border, so global `winborder` settings no longer add nested borders inside the picker.
  - The outer Wayfinder frame still keeps its configured border style.
  - This came in via PR #6. Thanks to @tomerlevy1 for the contribution.

- **Small editor crash**
  - Fixed a case where very narrow editor windows could drive the preview pane width to zero or below and crash Wayfinder with an invalid float width error.

**Changed**

- **Graceful narrow-window fallback**
  - Wayfinder now detects when the current editor is too small for the 3-pane layout, shows a short warning, and aborts cleanly instead of half-opening broken UI state.

- **Regression coverage for layout sizing**
  - Added a headless test for the too-small editor path so layout changes can keep this failure mode from regressing.

---

## Changes 04/29/2026 (v0.1.8)

`fix(v0.1.8): refine Trail pinning flow and preview context`

**Commit message**

```text
fix(v0.1.8): refine Trail pinning flow and preview context

- trail(pin): stop auto-switching into the Trail facet when pinning multiple items
- ui(list): mark already-pinned items on the second row of each result
- ui(topbar): keep Trail item counts visible after pin notices expire
- keys(filter): add <C-l> to clear the current local filter in-place
- preview(header): show a project-relative path line above the snippet so file context is visible without taking over the preview
```

**Changed**

- **Lighter pin flow**
  - Pinning no longer forces Wayfinder into the `Trail` facet after the second item, so collecting several items in a row stays focused on the current facet.

- **Pinned item markers**
  - Result rows now show a small pinned marker on the second line once an item has already been added to Trail.

- **Persistent Trail status**
  - The top bar now keeps a steady `Trail • N items` status after the temporary `Pinned to Trail` notice expires, so the Trail state stays visible across facet changes.

- **Faster filter reset**
  - Added `<C-l>` inside Wayfinder to clear the current local filter and rerender immediately without reopening the picker.

- **Preview file context**
  - The preview pane now uses a project-relative path line above the snippet instead of starting code on the first row.
  - This keeps the current file context visible while leaving the code preview itself as the main focus.

---

## Changes 04/29/2026 (v0.1.7)

`release(v0.1.7): add smarter local filter terms`

**Commit message**

```text
release(v0.1.7): add smarter local filter terms

- filter(query): support space-separated include terms with AND matching
- filter(negation): support !term exclusions in the local Wayfinder filter
- filter(phrases): support double-quoted exact phrases in local filter queries
```

**Added**

- **Smarter local filter queries**
  - Added space-separated positive terms with AND semantics to Wayfinder's local `/` filter.
  - Added negated terms with `!term` so obvious noise can be excluded quickly.
  - Added double-quoted phrase matching for exact multi-word terms.

**Changed**

- **Filter matching behavior**
  - Local filtering now matches against `label`, `secondary`, and `detail` using parsed include/exclude terms instead of a single raw substring.

- **Demo media refresh**
  - Refreshed the README screenshots and animated demo to show the current Wayfinder flow, including local filter usage, result movement, Trail pinning, and jump behavior.

---

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
