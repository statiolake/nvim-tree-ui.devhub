-- nvim-tree-ui.devhub: nvim-tree drawn as DevHub's native file tree.
--
-- nvim-tree stays the model and keeps the keys: its buffer, its window, its
-- mappings (yours, from on_attach), actions, git, diagnostics, filters and
-- prompts are untouched. Only the drawing changes: nvim-tree's buffer
-- becomes a `gui.view` (devhub.nvim) in tree form — each line one row,
-- indented by its depth with guides down the rows, the cursor line the
-- focused row — painted over nvim-tree's own window. So every key does what
-- it does in nvim-tree, by construction.
--
-- A DevHub extension: it needs DevHub's GUI and devhub.nvim, and is meant
-- to be loaded only there. When nvim-tree's internals are not what it
-- expects (another version), nvim-tree draws itself.

local rows = require 'nvim-tree-ui.rows'

local M = {}

-- The look: 22 px rows, a level 16 px (the chevron's column, the guides
-- down its middle), 6 px between the parts of a row.
M.INDENT = 16
M.ROW_HEIGHT = 22
M.GAP = 6

local defaults = {
  enabled = true,
  -- The hint row under the tree: { { lhs, label } }; none by default.
  keys = nil,
}

M.config = vim.deepcopy(defaults)

-- buf -> { view, tick, snapshot }
local attached = {}

function M.active()
  local g = vim.g.nvim_tree_ui_devhub
  if g ~= nil then
    return g ~= false
  end
  return M.config.enabled ~= false
end

-- nvim-tree's internals this needs, or nil (then nvim-tree draws itself).
local function internals()
  local ok, core = pcall(require, 'nvim-tree.core')
  local okv, view = pcall(require, 'nvim-tree.view')
  if not ok or not okv then
    return nil
  end
  local explorer = type(core.get_explorer) == 'function' and core.get_explorer() or nil
  if not explorer or type(explorer.get_nodes_by_line) ~= 'function' or type(core.get_nodes_starting_line) ~= 'function' then
    return nil
  end
  return { core = core, view = view, explorer = explorer }
end

local function depth_of(node)
  local d = -1
  local p = node.parent
  while p do
    d = d + 1
    p = p.parent
  end
  return math.max(d, 0)
end

-- What every line of this render is: nodes by line, the header lines,
-- the signs. Made once per change of the buffer.
local function snapshot(buf)
  local a = attached[buf]
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if a.snap and a.tick == tick then
    return a.snap
  end
  local nt = internals()
  if not nt then
    return nil
  end
  local explorer = nt.explorer
  local start = nt.core.get_nodes_starting_line()
  local root_visible = nt.view.is_root_folder_visible(explorer.absolute_path)
  a.snap = {
    explorer = explorer,
    by_line = explorer:get_nodes_by_line(start),
    root_line = root_visible and 1 or nil,
    filter_line = explorer.live_filter and explorer.live_filter.filter and (start - 1) or nil,
    signs = rows.signs(buf),
  }
  a.tick = tick
  return a.snap
end

local function filter_typing()
  return vim.bo.filetype == 'NvimTreeFilter'
end

function M.item(buf, lnum, line)
  local snap = snapshot(buf)
  if not snap then
    return nil
  end
  if lnum == snap.root_line then
    return { node = rows.root_row(snap.explorer.absolute_path), sticky = true, depth = 0 }
  end
  if lnum == snap.filter_line then
    return { node = rows.filter_row(snap.explorer.live_filter.filter or '', filter_typing()), sticky = true, depth = 0 }
  end
  local node = snap.by_line[lnum]
  if not node then
    return nil
  end
  local ok, hn = pcall(function()
    return node:highlighted_name()
  end)
  local name = ok and hn and hn.str or node.name
  local kind = node.nodes and 'directory' or node.type == 'link' and 'link' or 'file'
  local okg, ignored = pcall(function()
    return node:is_git_ignored()
  end)
  local info = { kind = kind, open = node.open == true, depth = depth_of(node), ignored = okg and ignored == true }
  local row = rows.node_row(info, rows.parts(buf, lnum, line, name, snap.signs), M.GAP)
  local hidden = rows.virtual_lines(buf, lnum)
  if #hidden > 0 then
    local col = { type = 'stack', children = { row } }
    for _, h in ipairs(hidden) do
      table.insert(col.children, {
        type = 'text',
        size = 'xs',
        runs = { { text = h, hl = 'NvimTreeHiddenDisplay' } },
      })
    end
    row = col
  end
  return { node = row, depth = info.depth }
end

-- A double click does what the tree's <2-LeftMouse> does (nvim-tree's, or
-- the one your on_attach set); a single click only moves the cursor, as in
-- nvim-tree.
local function on_click(buf, lnum, clicks)
  if clicks ~= 2 then
    return
  end
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == '<2-LeftMouse>' then
      if map.callback then
        map.callback()
      elseif map.rhs then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(map.rhs, true, true, true), 'm', false)
      end
      return
    end
  end
  local _ = lnum
end

function M.attach(buf)
  if attached[buf] or not M.active() or not vim.api.nvim_buf_is_valid(buf) or not internals() then
    return
  end
  local gui = require('devhub').gui
  if not gui.available() then
    return
  end
  attached[buf] = {}
  local view = gui.view {
    buf = buf,
    indent = M.INDENT,
    row_height = M.ROW_HEIGHT,
    keys = M.config.keys,
    items = function(lnum, line)
      local ok, item = pcall(M.item, buf, lnum, line)
      return ok and item or nil
    end,
    on_click = function(lnum, clicks)
      on_click(buf, lnum, clicks)
    end,
  }
  if not view then
    attached[buf] = nil
    return
  end
  attached[buf].view = view
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      attached[buf] = nil
    end,
  })
end

function M.detach(buf)
  local a = attached[buf]
  attached[buf] = nil
  if a and a.view then
    a.view:close()
  end
end

-- nvim-tree moved the cursor itself (after a render, find_file): place the
-- focus again.
local function redraw_all()
  for _, a in pairs(attached) do
    if a.view then
      a.view:redraw()
    end
  end
end

local installed = false
function M.install()
  if installed then
    return
  end
  local ok, api = pcall(require, 'nvim-tree.api')
  if not ok or not api.events then
    return
  end
  installed = true
  local E = api.events.Event
  api.events.subscribe(E.TreeAttachedPost, function(buf)
    vim.schedule(function()
      M.attach(buf)
    end)
  end)
  api.events.subscribe(E.TreeRendered, function(data)
    if data and data.bufnr and not attached[data.bufnr] then
      M.attach(data.bufnr)
    end
    redraw_all()
  end)
  local group = vim.api.nvim_create_augroup('nvim_tree_ui_devhub', { clear = true })
  -- The live filter's float: hidden, its text drawn in the tree's filter
  -- row (its keys stay its buffer's).
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'NvimTreeFilter',
    callback = function(ev)
      if not M.active() or next(attached) == nil then
        return
      end
      for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
        pcall(vim.api.nvim_win_set_config, win, { hide = true })
      end
    end,
  })
  -- Typing in the filter or leaving it changes the field's caret.
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufLeave', 'TextChangedI' }, {
    group = group,
    callback = function()
      if vim.bo.filetype == 'NvimTreeFilter' then
        for b, a in pairs(attached) do
          a.tick = nil
          if a.view then
            a.view:update()
          end
          local _ = b
        end
      end
    end,
  })
  -- A tree already open.
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'NvimTree' then
      M.attach(b)
    end
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  M.install()
end

return M
