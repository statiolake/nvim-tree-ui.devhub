# nvim-tree-ui.devhub

> **WIP — a prototype.** It draws the tree and keeps every nvim-tree key;
> the styles and the remaining items below are still being settled.

[nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua) drawn as
[DevHub](https://github.com/statiolake/devhub)'s native file tree: rows in
DevHub's type, a chevron per folder, indent guides down the rows, git and
diagnostics as small marks at the end of the row, the root as a section
header that stays at the top.

A DevHub extension (named `.devhub`, as Neovim plugins are `.nvim`): DevHub's
GUI is its engine, so it needs DevHub and devhub.nvim and is meant to be
loaded only there (the `cond` below); a terminal Neovim keeps plain
nvim-tree by not loading it.

## What stays nvim-tree's

Everything but the drawing. nvim-tree keeps its buffer, its window, its
mappings (`default_on_attach` and your `on_attach`), actions, git,
diagnostics, filters, marks, the live filter and the prompts. Its buffer
becomes a `gui.view` (devhub.nvim) in tree form — one row per line, its
cursor line the focused row — painted over nvim-tree's own window. Every key
is nvim-tree's by construction: nothing is mapped here.

- **Rows**: on every render (`TreeRendered`) the buffer is final; each line
  is read back as nvim-tree drew it — the icon, the name and the group over
  it (git, opened, modified, cut, copied, bookmarks, as you configured
  them), the icons after the name, the right-aligned ones and the sign —
  and the line's node (for its depth and whether it is an open folder) comes
  from nvim-tree's explorer.
- **Cursor**: DevHub follows the window's cursor; nvim-tree moving it itself
  (a render, `find_file`) redraws the focus.
- **Visual mode** (`V` then `d`, `x`, `c`, `m`, `gy`): the lines selected
  are drawn selected.
- **Mouse**: a click moves the cursor, a double click does what the tree's
  `<2-LeftMouse>` does; the wheel scrolls and takes the cursor along.
- **Live filter** (`f`): nvim-tree's one-line float is hidden and what is
  typed shows in the filter row; the keys are still the float's buffer's.
- **Prompts** (`a`, `r`, `d`): `vim.ui.input` / `vim.ui.select`, i.e.
  DevHub's quick pick with devhub.nvim's `quick_pick = true`.

When nvim-tree's internals are not what this expects (another version),
nvim-tree draws itself.

## Install

Needs nvim-tree.lua and [devhub.nvim](https://github.com/statiolake/devhub.nvim),
and a DevHub whose `gui.view` takes `indent` / `row_height` (a tree).

```lua
{
  'statiolake/nvim-tree-ui.devhub',
  cond = vim.env.DEVHUB_NEOVIM_GUI == '1',   -- only in DevHub's GUI
  dependencies = { 'nvim-tree/nvim-tree.lua', 'statiolake/devhub.nvim' },
  event = 'VeryLazy',
  main = 'nvim-tree-ui',
  opts = { style = 'native' },
}
```

## Options

```lua
require('nvim-tree-ui').setup {
  enabled = true,       -- false: nvim-tree draws itself
  style = 'native',     -- 'native' | 'compact' | 'minimal', or a table:
  --   { indent = 16, row_height = 22, gap = 6,
  --     icons = 'devicons' | 'codicon', git = 'letter' | 'dot' | 'glyph',
  --     diagnostics = 'icon' | 'pill', header = 'section' | 'path' }
  keys = nil,           -- a hint row: { { 'a', 'new' }, { 'r', 'rename' } }
}
```

`vim.g.nvim_tree_ui_devhub = true | false` turns it on or off while Neovim runs
(for trees opened afterwards).

## Still to do

- Rename in place (an inline field on the row) instead of the quick pick.
- Drag and drop between folders.
- A style chosen and the other two dropped.

## Tests

```sh
NVIM_TREE=~/.local/share/nvim/lazy/nvim-tree.lua \
  nvim --headless --clean --cmd 'set rtp^=.' -l tests/spec.lua
```
