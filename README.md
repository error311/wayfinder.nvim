# wayfinder.nvim

`wayfinder.nvim` is a guided code exploration tool for the current symbol.

Wayfinder is not a general search tool. It does not try to replace Telescope or grep.
It replaces the manual loop of jump, grep, back, open, back, and "where was that test again?"

From the current symbol or file, Wayfinder gathers the most relevant nearby code:

- definitions
- references
- callers
- likely tests
- recent commits

It opens as a centered 3-pane picker, loads sources progressively, and keeps the screen focused on facets, rows, badges, previews, and a Trail you can keep.

![wayfinder motion](docs/media/wayfinder.gif)

![wayfinder overview](docs/screenshots/overview.png)

![wayfinder refs](docs/screenshots/refs.png)

![wayfinder trail](docs/screenshots/trail.png)

## Features

- Centered 3-pane floating layout
- Facet rail with counts
- Dense result list with badges and grouped headers
- Syntax-highlighted preview
- Trail facet for pinned breadcrumbs
- Async LSP, tests, and git loading
- Local filter and jump actions

## Requirements

- Neovim `0.10+`

## Installation

With `lazy.nvim`:

```lua
{
  "error311/wayfinder.nvim",
  opts = {},
}
```

## Setup

```lua
require("wayfinder").setup({
  layout = {
    width = 0.88,
    height = 0.72,
  },
})
```

## Command

- `:Wayfinder`
- `:WayfinderExportQuickfix`
- `:WayfinderExportTrailQuickfix`
- `:WayfinderTrailNext`
- `:WayfinderTrailPrev`
- `:WayfinderTrailOpen`
- `:WayfinderTrailShow`
- `<Plug>(WayfinderOpen)`
- `<Plug>(WayfinderTrailNext)`
- `<Plug>(WayfinderTrailPrev)`
- `<Plug>(WayfinderTrailOpen)`
- `<Plug>(WayfinderTrailShow)`

Open it on a symbol for definitions, references, callers, likely tests, and recent commits.
If there is no symbol under the cursor, it falls back to the current file.

Recommended mapping:

```lua
vim.keymap.set("n", "<leader>wf", "<Plug>(WayfinderOpen)", { desc = "Wayfinder" })
```

Recommended Trail mappings:

```lua
vim.keymap.set("n", "<leader>wtn", "<Plug>(WayfinderTrailNext)", { desc = "Wayfinder Trail Next" })
vim.keymap.set("n", "<leader>wtp", "<Plug>(WayfinderTrailPrev)", { desc = "Wayfinder Trail Prev" })
vim.keymap.set("n", "<leader>wto", "<Plug>(WayfinderTrailOpen)", { desc = "Wayfinder Trail Open" })
vim.keymap.set("n", "<leader>wts", "<Plug>(WayfinderTrailShow)", { desc = "Wayfinder Trail Show" })
```

## Default Keys

- `j` / `k` move
- `gg` / `G` first / last result
- `<PageUp>` / `<PageDown>` page movement
- `<C-u>` / `<C-d>` move by half a page
- `h` / `l` switch facet
- `<Tab>` next facet
- `<S-Tab>` previous facet
- `<CR>` jump
- `s` open in split
- `v` open in vsplit
- `t` open in tab
- `p` pin into Trail
- `P` open Trail immediately
- `x` export current facet to quickfix
- `dd` remove pinned trail item
- `da` clear Trail
- `/` filter
- `D` toggle details
- `r` refresh
- `q` close
- mouse wheel scrolls results

Pinning behavior:

- the first `p` pins the current item
- after the second pin, Wayfinder switches to `Trail` automatically
- the top bar shows a short Trail hint when you pin an item

Trail commands outside Wayfinder:

- `:WayfinderTrailNext` opens the next Trail item
- `:WayfinderTrailPrev` opens the previous Trail item
- `:WayfinderTrailOpen` opens the current Trail item
- `:WayfinderTrailShow` opens Wayfinder on the Trail facet

Quickfix export:

- `:WayfinderExportQuickfix` exports the current visible facet in its current order
- `:WayfinderExportTrailQuickfix` exports Trail in Trail order

## Result Types

- `Calls` shows LSP definitions and callers
- `Refs` is split into `LSP References` and `Text Matches`
- `Tests` is heuristic and intentionally ranked below calls and refs
- `Git` shows recent commits touching the current file

## Demo Fixture

The repo includes a small fixture app plus a tiny demo LSP so screenshots and gifs are reproducible.

```sh
nvim -u demo/minimal_init.lua demo/fixture-app/src/user_service.ts
```

Move the cursor onto `createUser`, then run `:Wayfinder`.

More demo notes are in [demo/README.md](demo/README.md).

## Health

```vim
:checkhealth wayfinder
```

## License

MIT
