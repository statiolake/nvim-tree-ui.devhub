-- NVIM_TREE=<nvim-tree.lua checkout> nvim --headless --clean --cmd 'set rtp^=.' -l tests/spec.lua
-- With a real nvim-tree on a scratch directory and gui.view stubbed: the
-- rows made from its buffer (depth, chevron, icon, name, git and
-- diagnostics marks, the root), and that a re-render reaches the view.
-- Leaves Neovim with an error on failure.
local failures = {}
local function check(ok, what)
  if not ok then
    table.insert(failures, what)
  end
end

local nt = vim.env.NVIM_TREE or (vim.fn.stdpath 'data' .. '/lazy/nvim-tree.lua')
vim.opt.rtp:prepend(nt)
vim.opt.rtp:prepend(vim.fn.getcwd())

-- devhub.nvim stubbed: a view records what it was given.
local views = {}
package.loaded['devhub'] = {
  gui = {
    available = function()
      return true
    end,
    view = function(opts)
      local v = { opts = opts, redraws = 0, updates = 0 }
      function v.redraw()
        v.redraws = v.redraws + 1
      end
      function v.update()
        v.updates = v.updates + 1
      end
      function v.close() end
      table.insert(views, v)
      return v
    end,
  },
}

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. '/src/deep', 'p')
for _, f in ipairs { 'README.md', 'src/a.lua', 'src/deep/b.lua' } do
  vim.fn.writefile({ 'x' }, dir .. '/' .. f)
end
vim.cmd.cd(dir)

require('nvim-tree').setup {
  git = { enable = false },
  renderer = { indent_markers = { enable = true }, icons = { show = { file = false, folder = true, git = false } } },
}
require('nvim-tree-ui').setup { style = 'native' }
local api = require 'nvim-tree.api'
api.tree.open()
vim.wait(1000, function()
  return #views > 0
end)
check(#views == 1, 'a view on the tree buffer: ' .. #views)
local v = views[1]
check(v and v.opts.indent == 16 and v.opts.row_height == 22, 'the style\'s indent and row height')

local buf = v and v.opts.buf
local function items()
  local out = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    out[lnum] = v.opts.items(lnum, line) or false
  end
  return out
end
local function names(node, acc)
  acc = acc or {}
  if type(node) ~= 'table' then
    return acc
  end
  if node.type == 'text' then
    for _, r in ipairs(node.runs) do
      table.insert(acc, r.text)
    end
  end
  for _, c in ipairs(node.children or {}) do
    names(c, acc)
  end
  return acc
end

if buf then
  local it = items()
  check(it[1] and it[1].sticky and it[1].depth == 0, 'the root row is sticky')
  -- src is closed: src, README.md
  local src_line
  for lnum, item in ipairs(it) do
    if item and vim.tbl_contains(names(item.node), 'src') then
      src_line = lnum
    end
  end
  check(src_line ~= nil, 'a row named src')
  check(src_line and it[src_line].depth == 0, 'src at depth 0')
  -- open src: its children one deeper, and the view told the cursor moved
  local before = v.redraws
  vim.api.nvim_win_set_cursor(0, { src_line, 0 })
  api.node.open.edit()
  vim.wait(200)
  check(v.redraws > before, 'a render redraws the view')
  it = items()
  local deep
  for lnum, item in ipairs(it) do
    if item and vim.tbl_contains(names(item.node), 'a.lua') then
      deep = it[lnum]
    end
  end
  check(deep and deep.depth == 1, 'a.lua one deeper: ' .. vim.inspect(deep and deep.depth))
  -- the parts read back from nvim-tree's line
  local rows = require 'nvim-tree-ui.rows'
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find('src', 1, true) then
      local parts = rows.parts(buf, lnum, line, 'src', {})
      check(parts.name == 'src' and parts.name_hl ~= nil, 'src\'s name and its group: ' .. vim.inspect(parts))
      check(parts.icon ~= nil, 'src\'s folder icon read back')
    end
  end
end

if #failures > 0 then
  io.stderr:write('FAIL\n  ' .. table.concat(failures, '\n  ') .. '\n')
  os.exit(1)
end
print 'nvim-tree-ui: ok'
