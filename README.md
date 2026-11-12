# nvim-tree-ui.devhub

[nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua) drawn as
[DevHub](https://github.com/statiolake/devhub)'s native file tree: rows in
DevHub's type, 22 px tall; a chevron per folder and indent guides down the
rows (the one of the cursor's level stronger); your devicons; git as VS
Code reads it — a file's `M` / `A` / `U` / `D` / `R` at the end of its
row, a folder's one dot in its children's strongest status, ignored names
greyed —; diagnostics as your sign icon at the end of the row; the root as
a section header (`SAMPLE ~/work`) that stays at the top.

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
- **Marks** (`x`, `c`, `m`, `p`, clearing): a cut file shows scissors at
  the end of its row and its name greyed, a copied one a copy icon, a
  bookmarked one nvim-tree's bookmark glyph (beside a diagnostic, not
  instead of it). They are read from nvim-tree's own state (its marks and
  its clipboard), else from what it drew, and change at the render each
  of those keys makes.
- **Visual mode** (`V` then `d`, `x`, `c`, `m`, `gy`): the lines selected
  are one band, as a selection is in any list.
- **Mouse**: a click moves the cursor, a double click does what the tree's
  `<2-LeftMouse>` does; the wheel scrolls and takes the cursor along.
- **Live filter** (`f`): nvim-tree's one-line float is hidden and what is
  typed shows in the filter row; the keys are still the float's buffer's.
- **Prompts** (`a`, `r`, `d`): `vim.ui.input` / `vim.ui.select`, i.e.
  DevHub's quick pick with devhub.nvim's `quick_pick = true`.

When nvim-tree's internals are not what this expects (another version),
nvim-tree draws itself.

## Requirements

- [DevHub](https://github.com/statiolake/devhub) with tree views:
  `gui.view{ indent, row_height }` and items `{ node, depth, sticky }`
  (`5033a5cb`, "gui.view as a tree") — and, for the selection drawn as one
  band, `b79811d0` or later. An older DevHub draws the rows without indent
  or guides.
- [devhub.nvim](https://github.com/statiolake/devhub.nvim) (`4df8ed1` or
  later documents and checks tree items).
- nvim-tree.lua (tested at `7e1da84`) and, for the icons,
  nvim-web-devicons — as you configure them for nvim-tree.

## Install

```lua
{
  'statiolake/nvim-tree-ui.devhub',
  cond = vim.env.DEVHUB_NEOVIM_GUI == '1',   -- only in DevHub's GUI
  dependencies = { 'nvim-tree/nvim-tree.lua', 'statiolake/devhub.nvim' },
  event = 'VeryLazy',
  main = 'nvim-tree-ui',
  opts = {},
}
```

Keep your nvim-tree spec as it is: `on_attach`, `renderer`, `git`,
`diagnostics` and the rest are read from what nvim-tree draws.

## Options

```lua
require('nvim-tree-ui').setup {
  enabled = true,       -- false: nvim-tree draws itself
  keys = nil,           -- a hint row under the tree: { { 'a', 'new' }, { 'r', 'rename' } }
}
```

`vim.g.nvim_tree_ui_devhub = true | false` turns it on or off while Neovim runs
(for trees opened afterwards).

## Not (yet) here

- Rename in place on the row: `r` / `a` ask in DevHub's quick pick.
- Drag and drop between folders.
- Scrolling is DevHub's, in pixels, keeping the cursor's row in sight:
  `zz` / `zt` move nothing you can see.

## Tests

```sh
NVIM_TREE=~/.local/share/nvim/lazy/nvim-tree.lua \
  nvim --headless --clean --cmd 'set rtp^=.' -l tests/spec.lua
```
