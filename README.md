# wayfinder.nvim

`wayfinder.nvim` is a guided code exploration picker for the current symbol or file.

It is not a general search tool, and it does not try to replace Telescope or grep.
It replaces the manual loop of jump, grep, back, open, back, and "where was that test again?"

Wayfinder opens a centered 3-pane picker and gathers connected code:

- definitions
- references
- callers
- likely tests
- recent commits

Pin useful stops into Trail while you explore, then save that Trail per project and resume it later.

![wayfinder motion](docs/media/wayfinder.gif)

![wayfinder overview](docs/screenshots/overview.png)

![wayfinder refs](docs/screenshots/refs.png)

![wayfinder trail](docs/screenshots/trail.png)

## Features

- Centered 3-pane floating layout
- Facet rail, dense result rows, badges, and grouped headers
- Syntax-highlighted preview with project-relative context
- `e` pivots from the selected code row without leaving the picker
- `b` / `f` move backward and forward through explore history
- Top bar shows the selected row's explore target before pivoting
- Trail pins selected rows, current targets, and explore paths
- Persistent named Trails per project
- Toggleable bottom key hints
- Progressive, cancelable LSP, test, text, and git sources
- Local filter with negation and quoted phrases

## Requirements

- Neovim `0.10+`
- `ripgrep` for Text Matches
- `git` for the Git facet

## Installation

With `lazy.nvim`:

```lua
{
  "error311/wayfinder.nvim",
  opts = {},
}
```

## Quick Start

```lua
require("wayfinder").setup({})

vim.keymap.set("n", "<leader>wf", "<Plug>(WayfinderOpen)", {
  desc = "Wayfinder",
})
```

Open Wayfinder on a symbol to see definitions, references, callers, likely tests, and recent commits.
If there is no symbol under the cursor, Wayfinder falls back to the current file.

## Typical Flow

1. Open Wayfinder on the current symbol or file.
2. Move across `Calls`, `Refs`, `Tests`, `Git`, and `Trail`.
3. Use preview to confirm the right match before jumping.
4. Press `e` to explore from the selected code result.
5. Use `b` / `f` to move through explore history.
6. Use `a` to add the current target to Trail, or `A` to add the whole explore path.
7. Pin selected rows with `p`.
8. Save, load, or resume a Trail if you want to keep that path.

## Default Keys

| Key | Action |
| --- | --- |
| `j` / `k` | Move selection |
| `gg` / `G` | First / last result |
| `<C-u>` / `<C-d>` | Move by half a page |
| `h` / `l` | Previous / next facet |
| `<Tab>` / `<S-Tab>` | Next / previous facet |
| `<CR>` | Jump |
| `e` | Explore selected code result |
| `b` / `f` | Back / forward through explore history |
| `p` | Pin selected row into Trail |
| `a` | Add current Wayfinder target to Trail |
| `A` | Add current explore path to Trail |
| `P` | Open Trail |
| `S` | Open Trail menu |
| `[` / `]` | Previous / next saved Trail |
| `s` / `v` / `t` | Open in split / vsplit / tab |
| `/` / `<C-l>` | Filter / clear filter |
| `D` | Toggle details |
| `?` | Toggle bottom key hints |
| `x` | Export current facet to quickfix |
| `dd` / `da` | Remove Trail item / clear Trail |
| `r` | Refresh |
| `q` | Close |

## Trail

Trail is the breadcrumb list you build while exploring.

- `p` pins the selected row.
- `a` pins the current Wayfinder target.
- `A` pins the current explore path.
- Trail groups explicit explore targets separately from selected row pins.
- `S` opens save, resume, load, rename, and delete actions.
- Saved Trails are project-scoped and stored under Neovim state, not in your repo.

Normal `:Wayfinder` opens do not auto-load saved Trails. Use `:WayfinderTrailResume` or the Trail menu when you want to restore the last active saved Trail.

## Explore

`e` pivots Wayfinder from the selected code row. The top bar shows what will be explored, such as `Explore findUser`, before the pivot happens.

`D` details include the exact explore target location when there is room. Git rows are history rows, so they explain why they cannot be explored instead of pivoting.

## Configuration

Default setup is enough for normal repos. A small layout tweak looks like this:

```lua
require("wayfinder").setup({
  layout = {
    width = 0.88,
    height = 0.72,
    show_hints = true,
  },
})
```

For large repos or monorepos, narrow broad sources to the nearest package/module:

```lua
require("wayfinder").setup({
  performance = "fast",
  scope = {
    mode = "package",
    package_markers = {
      "package.json",
      "tsconfig.json",
      "pyproject.toml",
      "go.mod",
      "Cargo.toml",
      ".git",
    },
  },
})
```

Performance presets:

- `fast`: tighter limits and shorter timeouts
- `balanced`: default behavior
- `full`: broader limits and looser timeouts

## Commands

Core commands:

- `:Wayfinder`
- `:WayfinderExportQuickfix`
- `:WayfinderExportTrailQuickfix`

Trail commands:

- `:WayfinderTrailNext`
- `:WayfinderTrailPrev`
- `:WayfinderTrailOpen`
- `:WayfinderTrailShow`
- `:WayfinderTrailSave`
- `:WayfinderTrailSaveAs`
- `:WayfinderTrailLoad`
- `:WayfinderTrailResume`
- `:WayfinderTrailDelete`
- `:WayfinderTrailRename`

Recommended external mappings:

```lua
vim.keymap.set("n", "<leader>wf", "<Plug>(WayfinderOpen)", { desc = "Wayfinder" })
vim.keymap.set("n", "<leader>wtn", "<Plug>(WayfinderTrailNext)", { desc = "Wayfinder Trail Next" })
vim.keymap.set("n", "<leader>wtp", "<Plug>(WayfinderTrailPrev)", { desc = "Wayfinder Trail Prev" })
vim.keymap.set("n", "<leader>wto", "<Plug>(WayfinderTrailOpen)", { desc = "Wayfinder Trail Open" })
vim.keymap.set("n", "<leader>wts", "<Plug>(WayfinderTrailShow)", { desc = "Wayfinder Trail Show" })
```

## Help

For full behavior and configuration details:

```vim
:help wayfinder
:checkhealth wayfinder
```

## Demo Fixture

The repo includes a small fixture app plus a tiny demo LSP so screenshots and gifs are reproducible.

```sh
nvim -u demo/minimal_init.lua demo/fixture-app/src/user_service.ts
```

Move the cursor onto `createUser`, then run `:Wayfinder`.

More demo notes are in [demo/README.md](demo/README.md).

## License

MIT
