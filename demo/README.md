# Demo

`wayfinder.nvim` ships with a small fixture app and a tiny fake LSP server so the UI can be captured without external setup.

## Run

From the repo root:

```sh
nvim -u demo/minimal_init.lua demo/fixture-app/src/user_service.ts
```

Then:

1. Put the cursor on `createUser`.
2. Run `:Wayfinder`.
3. Use `h` and `l` to move between `Calls`, `Refs`, `Tests`, `Git`, and `Trail`.
4. Press `p` on two or three items to build a Trail.
5. Press `<CR>` on a Trail item to jump.

## Recommended Capture Flow

1. Open on `createUser`.
2. Start on `Calls`.
3. Move into `Refs` so both `LSP References` and `Text Matches` are visible.
4. Pin a caller, a ref, and a test.
5. Switch to `Trail`.
6. Capture one still on `Calls`, one on `Refs`, and one on `Trail`.

## Included Pieces

- `demo/minimal_init.lua`
  Loads the plugin with a clean demo config.
- `demo/fake_lsp.py`
  Provides definitions, references, and callers for the fixture app.
- `demo/fixture-app`
  Small fixture app with callers, refs, tests, and text matches for screenshots.
