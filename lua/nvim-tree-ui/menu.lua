-- The tree's right-click menu (and <S-F10>'s): what nvim-tree's public API
-- does to the node, as a native menu (devhub.nvim's gui.view
-- on_context_menu). Only what is valid for the node is offered — a file's
-- opens, a folder's expand, the root's few — and Paste only while nvim-tree's
-- clipboard holds something. Each item shows the key your nvim-tree
-- mappings give the same action (api.map.keymap.current()), so the menu
-- teaches the keys.

local M = {}

-- lhs of the keys your on_attach maps to each action: by the function
-- (`vim.keymap.set('n', 'r', api.fs.rename)`), else by nvim-tree's desc.
local function key_index(keymap)
  local by_fn, by_desc = {}, {}
  for _, map in ipairs(keymap or {}) do
    local lhs = map.lhs
    local mode = map.mode
    if type(lhs) == 'string' and (mode == nil or mode == 'n' or mode == ' ') and not lhs:find('Mouse', 1, true) then
      lhs = lhs:gsub('^<[Ll]eader>', vim.g.mapleader or '\\')
      if map.callback then
        by_fn[map.callback] = by_fn[map.callback] or {}
        table.insert(by_fn[map.callback], lhs)
      end
      if type(map.desc) == 'string' then
        local desc = map.desc:gsub('^nvim%-tree: ', '')
        by_desc[desc] = by_desc[desc] or {}
        table.insert(by_desc[desc], lhs)
      end
    end
  end
  return by_fn, by_desc
end

-- The one key to show of several: a named key (`<CR>`, `<C-v>`), then a
-- single key (`r`), then a sequence (`gy`).
local function rank(lhs)
  if lhs:match '^<[^<>]+>$' then
    return 1
  end
  if vim.fn.strchars(lhs) == 1 then
    return 2
  end
  return 3
end

function M.best_key(keys)
  if not keys or #keys == 0 then
    return nil
  end
  local best
  for _, lhs in ipairs(keys) do
    if not best or rank(lhs) < rank(best) then
      best = lhs
    end
  end
  return best
end

-- The key for an action: by its function, else nvim-tree's own name for it.
function M.keys_for(index, fn, desc)
  local by_fn, by_desc = index[1], index[2]
  return M.best_key(fn and by_fn[fn]) or M.best_key(desc and by_desc[desc])
end

local function clipboard_has(explorer)
  local ok, has = pcall(function()
    local data = explorer.clipboard.data
    return #data.copy > 0 or #data.cut > 0
  end)
  return ok and has
end

local function trash_configured(explorer)
  local ok, cmd = pcall(function()
    return explorer.opts.trash.cmd
  end)
  if not ok or type(cmd) ~= 'string' or cmd == '' then
    return false
  end
  return vim.fn.executable(vim.split(cmd, ' ', { trimempty = true })[1] or '') == 1
end

-- New Folder…: nvim-tree's create asks for a name and makes a folder of one
-- ending in /; this asks for the folder's name and makes it there.
local function new_folder(api, dir)
  vim.ui.input({ prompt = 'New Folder in ' .. vim.fn.fnamemodify(dir, ':~') .. '/' }, function(name)
    if not name or vim.trim(name) == '' then
      return
    end
    local path = dir .. '/' .. vim.trim(name):gsub('/+$', '')
    if vim.uv.fs_stat(path) then
      vim.notify(vim.fn.fnamemodify(path, ':~') .. ' already exists', vim.log.levels.WARN)
      return
    end
    if vim.fn.mkdir(path, 'p') ~= 1 then
      vim.notify('could not make ' .. vim.fn.fnamemodify(path, ':~'), vim.log.levels.ERROR)
      return
    end
    api.tree.reload()
    pcall(api.tree.find_file, { buf = path, open = false, focus = false })
  end)
end

--- The menu for line lnum of the tree: the node there (nil: the filter row,
--- nothing), `root` when it is the root's row. `deps`: { api, explorer,
--- keymap, mac } (keymap: api.map.keymap.current(); mac: Reveal in Finder).
function M.items(node, root, deps)
  local api, explorer = deps.api, deps.explorer
  if not node then
    return nil
  end
  local index = { key_index(deps.keymap) }
  local function item(label, fn, desc, run, enabled)
    return {
      label = label,
      accelerator = M.keys_for(index, fn, desc),
      enabled = enabled,
      on_select = run or function()
        fn(node)
      end,
    }
  end
  local sep = { separator = true }
  local dir = node.nodes ~= nil
  local items = {}
  local function add(...)
    for _, it in ipairs { ... } do
      table.insert(items, it)
    end
  end
  local folder = dir and node.absolute_path or vim.fn.fnamemodify(node.absolute_path, ':h')

  if root then
    add(
      item('New File…', api.fs.create, 'Create File Or Directory'),
      item('New Folder…', nil, nil, function()
        new_folder(api, node.absolute_path)
      end)
    )
    if clipboard_has(explorer) then
      add(sep, item('Paste', api.fs.paste, 'Paste'))
    end
    add(sep, item('Copy Absolute Path', api.fs.copy.absolute_path, 'Copy Absolute Path'))
    if deps.mac then
      add(item('Reveal in Finder', nil, nil, function()
        vim.fn.jobstart({ 'open', '-R', node.absolute_path }, { detach = true })
      end))
    end
    add(sep, item('Collapse All', api.tree.collapse_all, 'Collapse All', function()
      api.tree.collapse_all()
    end), item('Refresh', api.tree.reload, 'Refresh', function()
      api.tree.reload()
    end))
    return items
  end

  if dir then
    add(item(node.open and 'Collapse' or 'Expand', api.node.open.edit, 'Open'))
  else
    add(
      item('Open', api.node.open.edit, 'Open'),
      item('Open in Vertical Split', api.node.open.vertical, 'Open: Vertical Split'),
      item('Open in Horizontal Split', api.node.open.horizontal, 'Open: Horizontal Split'),
      item('Open in New Tab', api.node.open.tab, 'Open: New Tab')
    )
  end
  add(
    sep,
    item('New File…', api.fs.create, 'Create File Or Directory'),
    item('New Folder…', nil, nil, function()
      new_folder(api, folder)
    end),
    item('Rename…', api.fs.rename, 'Rename'),
    item('Delete', api.fs.remove, 'Delete')
  )
  if trash_configured(explorer) then
    add(item('Trash', api.fs.trash, 'Trash'))
  end
  add(sep, item('Cut', api.fs.cut, 'Cut'), item('Copy', api.fs.copy.node, 'Copy'))
  if clipboard_has(explorer) then
    add(item('Paste', api.fs.paste, 'Paste'))
  end
  add(
    sep,
    item('Copy Name', api.fs.copy.filename, 'Copy Name'),
    item('Copy Relative Path', api.fs.copy.relative_path, 'Copy Relative Path'),
    item('Copy Absolute Path', api.fs.copy.absolute_path, 'Copy Absolute Path')
  )
  if deps.mac then
    add(item('Reveal in Finder', nil, nil, function()
      vim.fn.jobstart({ 'open', '-R', node.absolute_path }, { detach = true })
    end))
  end
  add(
    sep,
    item('Toggle Bookmark', api.marks.toggle, 'Toggle Bookmark'),
    item('Collapse All', api.tree.collapse_all, 'Collapse All', function()
      api.tree.collapse_all()
    end),
    item('Refresh', api.tree.reload, 'Refresh', function()
      api.tree.reload()
    end)
  )
  return items
end

return M
