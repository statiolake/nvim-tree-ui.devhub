-- One nvim-tree buffer line as a DevHub row.
--
-- nvim-tree has already decided what the line says: its icon, its name and
-- the groups over them (git, diagnostics, opened, modified, cut, copied,
-- bookmarks — combined as the person configured), the icons after the name
-- (git_placement = 'after'), the right-aligned ones and the sign. This
-- module reads that back (the line's text, its highlight extmarks, its
-- right-aligned extmarks and its sign) and lays it out natively: the depth
-- from the tree, the arrow as a chevron, the name in DevHub's type, the
-- decorations as small marks at the end of the row.

local M = {}

local ns_hl = vim.api.nvim_create_namespace 'NvimTreeHighlights'
local ns_right = vim.api.nvim_create_namespace 'NvimTreeExtmarks'
local SIGN_GROUP = 'NvimTreeRendererSigns'

-- Codicons, in the Symbols Nerd Font DevHub ships.
local CHEVRON_RIGHT = '\u{eab6}'
local CHEVRON_DOWN = '\u{eab4}'
-- The clipboard's marks at the end of a row (Material, in the same font).
local CUT = '\u{f0190}' -- content-cut
local COPIED = '\u{f018f}' -- content-copy

-- What nvim-tree draws for its own marks, read when its state is not at
-- hand: the bookmark's sign or icon, the clipboard's name groups.
local BOOKMARK_GROUP = 'NvimTreeBookmarkIcon'
local CUT_GROUP = 'NvimTreeCutHL'
local COPIED_GROUP = 'NvimTreeCopiedHL'

-- nvim-tree's git groups, as a letter in its tone (VS Code's reading).
local GIT = {
  NvimTreeGitDirtyIcon = { letter = 'M', hl = 'NvimTreeGitDirtyIcon', rank = 3 },
  NvimTreeGitStagedIcon = { letter = 'A', hl = 'NvimTreeGitStagedIcon', rank = 5 },
  NvimTreeGitNewIcon = { letter = 'U', hl = 'NvimTreeGitNewIcon', rank = 4 },
  NvimTreeGitDeletedIcon = { letter = 'D', hl = 'NvimTreeGitDeletedIcon', rank = 2 },
  NvimTreeGitRenamedIcon = { letter = 'R', hl = 'NvimTreeGitRenamedIcon', rank = 6 },
  NvimTreeGitMergeIcon = { letter = '!', hl = 'NvimTreeGitMergeIcon', rank = 1 },
  NvimTreeGitIgnoredIcon = { letter = 'I', hl = 'NvimTreeGitIgnoredIcon', rank = 7 },
}

--- The line's runs: { text, from, to, group } (bytes, 0-based, end
--- exclusive), the innermost highlight over each piece last.
function M.runs(buf, lnum, line)
  local row = lnum - 1
  local spans, cuts = {}, { [0] = true, [#line] = true }
  local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, ns_hl, { row, 0 }, { row, -1 }, { details = true })
  for i, m in ipairs(ok and marks or {}) do
    local col, d = m[3], m[4] or {}
    if d.hl_group then
      local to = d.end_row and d.end_row > row and #line or math.min(d.end_col or #line, #line)
      if to > col then
        table.insert(spans, { from = col, to = to, group = d.hl_group, order = i })
        cuts[col], cuts[to] = true, true
      end
    end
  end
  local points = vim.tbl_keys(cuts)
  table.sort(points)
  local out = {}
  for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    local group
    for _, sp in ipairs(spans) do
      if sp.from <= a and sp.to >= b then
        group = sp.group -- later marks are added later: innermost last
      end
    end
    table.insert(out, { text = line:sub(a + 1, b), from = a, to = b, group = group })
  end
  return out
end

-- The groups (innermost last) over byte col.
local function group_at(runs, col)
  for _, r in ipairs(runs) do
    if r.from <= col and col < r.to then
      return r.group
    end
  end
end

-- Whitespace-separated words of [from, to) with their group.
local function words(runs, line, from, to)
  local out = {}
  local i = from + 1
  while i <= to do
    local s, e = line:find('%S+', i)
    if not s or s > to then
      break
    end
    e = math.min(e, to)
    table.insert(out, { text = line:sub(s, e), group = group_at(runs, s - 1) })
    i = e + 1
  end
  return out
end

--- The parts of a node's line: icon, name and the decorations nvim-tree
--- put after it, on its right and in its sign column.
function M.parts(buf, lnum, line, name, signs)
  local runs = M.runs(buf, lnum, line)
  local parts = { name = name, after = {}, right = {} }
  -- The name: the last place it stands (the indent and icon come before).
  local s, e
  local from = 1
  while true do
    local a, b = line:find(name, from, true)
    if not a then
      break
    end
    s, e, from = a, b, b + 1
  end
  if not s then
    parts.name = vim.trim(line)
    return parts
  end
  parts.name_hl = group_at(runs, s - 1)
  -- The icon: the last word before the name that is not the arrow or a
  -- marker (nvim-tree's own groups for those).
  for _, w in ipairs(words(runs, line, 0, s - 1)) do
    local g = w.group or ''
    if not (g:match '^NvimTreeIndentMarker' or g:match '^NvimTreeFolderArrow') then
      parts.icon = w
    end
  end
  parts.after = words(runs, line, e, #line)
  local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, ns_right, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true })
  for _, m in ipairs(ok and marks or {}) do
    for _, chunk in ipairs((m[4] or {}).virt_text or {}) do
      local text = vim.trim(chunk[1] or '')
      if text ~= '' then
        local g = chunk[2]
        table.insert(parts.right, { text = text, group = type(g) == 'table' and g[#g] or g })
      end
    end
  end
  parts.sign = signs and signs[lnum]
  return parts
end

--- Sign per line, as nvim-tree placed them: { [lnum] = { text, hl } }.
function M.signs(buf)
  local out = {}
  local ok, placed = pcall(vim.fn.sign_getplaced, buf, { group = SIGN_GROUP })
  for _, s in ipairs(ok and placed[1] and placed[1].signs or {}) do
    local def = vim.fn.sign_getdefined(s.name)[1]
    if def and def.text and vim.trim(def.text) ~= '' then
      out[s.lnum] = { name = s.name, text = vim.trim(def.text), hl = def.texthl }
    end
  end
  return out
end

-- Builders -------------------------------------------------------------------

local function text(runs, extra)
  return vim.tbl_extend('force', { type = 'text', runs = runs }, extra or {})
end

local function icon(glyph, hl, extra)
  return vim.tbl_extend('force', { type = 'icon', glyph = glyph, hl = hl }, extra or {})
end

-- The chevron's column: 16 px, a level's width, so the guides of the rows
-- under it run down its middle.
local function twistie(node)
  local glyph
  if node.kind == 'directory' then
    glyph = node.open and CHEVRON_DOWN or CHEVRON_RIGHT
  end
  return {
    type = 'hstack',
    children = {
      { type = 'spacer', size = 2 },
      glyph and icon(glyph, 'NvimTreeFolderArrowClosed', { size = 'sm' }) or { type = 'spacer', size = 12 },
      { type = 'spacer', size = 2 },
    },
  }
end

-- The marks at the end of a row: git as VS Code reads it (a file's letter,
-- a folder's one dot in its children's strongest status; anything else
-- nvim-tree put after the name as it is), then the right-aligned ones and
-- the diagnostic sign.
local function marks(parts)
  local out = {}
  local function add(node)
    table.insert(out, node)
  end
  local folder_git
  for _, w in ipairs(parts.after) do
    local git = w.group and GIT[w.group]
    if git and (not folder_git or git.rank < folder_git.rank) then
      folder_git = git
    end
  end
  local dotted = false
  for _, w in ipairs(parts.after) do
    local git = w.group and GIT[w.group]
    if git and parts.kind == 'directory' then
      if not dotted then
        dotted = true
        add(icon('●', folder_git.hl, { size = 'xs' }))
      end
    elseif git then
      add(text({ { text = git.letter, hl = git.hl, bold = true } }, { mono = true, size = 'sm' }))
    else
      add(text({ { text = w.text, hl = w.group } }, { mono = true, size = 'sm' }))
    end
  end
  for _, w in ipairs(parts.right) do
    add(text({ { text = w.text, hl = w.group } }, { mono = true, size = 'sm' }))
  end
  -- The marks nvim-tree keeps on a node: cut, copied, bookmarked.
  local marks_ = parts.marks or {}
  if marks_.cut then
    add(icon(CUT, 'Function', { size = 'sm', tip = 'cut' }))
  elseif marks_.copied then
    add(icon(COPIED, 'Function', { size = 'sm', tip = 'copied' }))
  end
  if marks_.bookmark then
    add(icon(marks_.bookmark.text, marks_.bookmark.hl, { size = 'sm', tip = 'bookmark' }))
  end
  -- The sign: a diagnostic (the bookmark's sign is drawn above already).
  if parts.sign and parts.sign.name ~= BOOKMARK_GROUP then
    add(icon(parts.sign.text, parts.sign.hl, { size = 'sm' }))
  end
  return out
end

--- The marks on a node: { bookmark = { text, hl }?, cut, copied } from
--- nvim-tree's state when the caller has it (state = { bookmark, cut,
--- copied, glyph }), else from what nvim-tree drew: the bookmark's sign or
--- icon, and the clipboard's group over the name.
function M.marks_of(parts, state)
  state = state or {}
  local glyph = state.glyph or '\u{f01a4}'
  local out = { cut = state.cut, copied = state.copied }
  if state.bookmark then
    out.bookmark = { text = glyph, hl = BOOKMARK_GROUP }
  end
  if parts.sign and parts.sign.name == BOOKMARK_GROUP then
    out.bookmark = out.bookmark or { text = parts.sign.text, hl = parts.sign.hl or BOOKMARK_GROUP }
  end
  for i = #parts.after, 1, -1 do
    local w = parts.after[i]
    if w.group == BOOKMARK_GROUP then
      out.bookmark = out.bookmark or { text = w.text, hl = BOOKMARK_GROUP }
      table.remove(parts.after, i) -- drawn as the bookmark, not as a plain mark
    end
  end
  if state.cut == nil and parts.name_hl == CUT_GROUP then
    out.cut = true
  end
  if state.copied == nil and parts.name_hl == COPIED_GROUP then
    out.copied = true
  end
  for i = #parts.right, 1, -1 do
    if parts.right[i].group == BOOKMARK_GROUP then
      out.bookmark = out.bookmark or { text = parts.right[i].text, hl = BOOKMARK_GROUP }
      table.remove(parts.right, i)
    end
  end
  return out
end

--- A node's row: chevron, icon, name, marks.
--- node = { kind = 'directory' | 'file' | 'link', open, depth, ignored }
function M.node_row(node, parts, gap)
  parts.kind = node.kind
  local children = { twistie(node) }
  if parts.icon then
    table.insert(children, icon(vim.fn.strcharpart(parts.icon.text, 0, 1), parts.icon.group))
  end
  parts.marks = M.marks_of(parts, node.marks)
  -- git-ignored (nvim-tree's state, or its ignored mark after the name)
  -- or cut: the name in the muted colour, as VS Code greys them. nvim-tree
  -- draws cut and copied as an undercurl, which a name in its colour alone
  -- would lose: they are marks at the end of the row instead.
  local ignored = node.ignored == true or parts.marks.cut == true
  for _, w in ipairs(parts.after) do
    if w.group == 'NvimTreeGitIgnoredIcon' then
      ignored = true
    end
  end
  table.insert(children, text({ { text = parts.name } }, { hl = ignored and 'Comment' or parts.name_hl, ink = true, grow = true }))
  vim.list_extend(children, marks(parts))
  return { type = 'hstack', gap = gap or 6, align = 'center', children = children }
end

--- The root's row: a section header, the folder's name and where it is.
function M.root_row(path)
  local name = vim.fn.fnamemodify(path, ':t')
  if name == '' then
    name = path
  end
  return {
    type = 'hstack',
    gap = 6,
    align = 'center',
    pad = { 4, 0 },
    children = {
      icon(CHEVRON_DOWN, 'Comment', { size = 'sm' }),
      text({ { text = name, bold = true } }, { upper = true, size = 'sm' }),
      text({ { text = vim.fn.fnamemodify(path, ':~:h'), hl = 'Comment' } }, { size = 'xs', grow = true }),
    },
  }
end

--- The live filter's line: a field with what is typed so far.
function M.filter_row(filter, typing)
  local runs = { { text = filter ~= '' and filter or ' ' } }
  if typing then
    table.insert(runs, { text = '▏', hl = 'Cursor' })
  end
  return {
    type = 'hstack',
    gap = 6,
    align = 'center',
    pad = { 2, 6 },
    round = true,
    bg = 'CursorLine',
    children = {
      icon('\u{ea6d}', 'Comment', { size = 'sm' }), -- search
      text(runs, { grow = true }),
    },
  }
end

--- The hidden-count line nvim-tree adds under a folder (virt_lines).
function M.virtual_lines(buf, lnum)
  local ns = vim.api.nvim_create_namespace 'NvimTreeVirtualLines'
  local ok, marks_ = pcall(vim.api.nvim_buf_get_extmarks, buf, ns, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true })
  local out = {}
  for _, m in ipairs(ok and marks_ or {}) do
    for _, vline in ipairs((m[4] or {}).virt_lines or {}) do
      local last = vline[#vline]
      if last and vim.trim(last[1] or '') ~= '' then
        table.insert(out, vim.trim(last[1]))
      end
    end
  end
  return out
end

return M
