# Changelog

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
