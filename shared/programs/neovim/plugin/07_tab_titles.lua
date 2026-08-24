-- Dynamic tab title management for Neovim.
-- Terminal tabs are titled "<job pid>:<directory>", file tabs by file name.

local M = {}

local custom_tab_names = {}
local custom_buf_names = {}
local last_focused = {} -- [tabpage handle] = os.time()

local function tabnr_to_handle(tabnr)
  local handles = vim.api.nvim_list_tabpages()
  for _, handle in ipairs(handles) do
    if vim.api.nvim_tabpage_get_number(handle) == tabnr then
      return handle
    end
  end
end

local function dim_color(color, factor)
  local r = math.min(255, math.max(0, math.floor(math.floor(color / 0x10000) * factor)))
  local g = math.min(255, math.max(0, math.floor(math.floor((color % 0x10000) / 0x100) * factor)))
  local b = math.min(255, math.max(0, math.floor((color % 0x100) * factor)))
  return r * 0x10000 + g * 0x100 + b
end

local function setup_dim_highlights()
  local base = vim.api.nvim_get_hl(0, { name = 'TabLine', link = false })
  local bg = base.bg
  local fg = base.fg

  local hl1 = { bg = bg }
  local hl2 = { bg = bg }
  if fg then
    hl1.fg = dim_color(fg, 0.65)
    hl2.fg = dim_color(fg, 0.4)
  end

  vim.api.nvim_set_hl(0, 'TabLineOld1', hl1)
  vim.api.nvim_set_hl(0, 'TabLineOld2', hl2)
end

local function get_tab_highlight(i, current_tab, tab_handle)
  if i == current_tab then
    return '%#TabLineSel#'
  end
  if not last_focused[tab_handle] then
    return '%#TabLineOld2#'
  end
  local now = os.time()
  local focused = last_focused[tab_handle]
  local nd = os.date('*t', now)
  local fd = os.date('*t', focused)
  if nd.year == fd.year and nd.yday == fd.yday then
    return '%#TabLine#'
  elseif (now - focused) < 7 * 86400 then
    return '%#TabLineOld1#'
  else
    return '%#TabLineOld2#'
  end
end

local function terminal_title(buf)
  local pid = vim.b[buf].terminal_job_pid
  local cwd = vim.b[buf].terminal_cwd or vim.fn.getcwd()
  local dir_name = cwd and (cwd:match('([^/]+)$') or cwd) or "terminal"
  if pid then
    return pid .. ":" .. dir_name
  end
  return dir_name
end

-- Get buffer title for a specific buffer
function M.get_buffer_title(bufnr)
  local buf = bufnr

  if not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end

  if custom_buf_names[buf] then
    return custom_buf_names[buf]
  end

  local buftype = vim.bo[buf].buftype
  local buf_name = vim.api.nvim_buf_get_name(buf)

  if buftype == 'terminal' then
    return terminal_title(buf)
  end

  if buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":t")
  end

  return "[No Name]"
end

-- Get tab title for a specific tab
function M.get_tab_title(tabnr)
  local handle = tabnr_to_handle(tabnr)
  if handle and custom_tab_names[handle] then
    return custom_tab_names[handle]
  end

  local tab_buffers = vim.fn.tabpagebuflist(tabnr)
  local current_buf = tab_buffers[vim.fn.tabpagewinnr(tabnr)]

  if not vim.api.nvim_buf_is_valid(current_buf) then
    return ""
  end

  local buftype = vim.bo[current_buf].buftype
  local buf_name = vim.api.nvim_buf_get_name(current_buf)

  if buftype == 'terminal' then
    return terminal_title(current_buf)
  end

  if buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":t")
  end

  return "[No Name]"
end

function M.set_tab_name(tabnr, name)
  local handle = tabnr_to_handle(tabnr)
  if not handle then return end
  if name and name ~= "" then
    custom_tab_names[handle] = name
  else
    custom_tab_names[handle] = nil
  end
  M.update_all_tab_titles()
end

function M.set_buf_name(bufnr, name)
  if name and name ~= "" then
    custom_buf_names[bufnr] = name
  else
    custom_buf_names[bufnr] = nil
  end
end

-- Update all tab titles
function M.update_all_tab_titles()
  vim.cmd('redrawtabline')
end

-- Custom tabline function
function M.tabline()
  local result = {}
  local tab_count = vim.fn.tabpagenr('$')
  local current_tab = vim.fn.tabpagenr()

  for i = 1, tab_count do
    local title = M.get_tab_title(i)

    if #title > 30 then
      title = title:sub(1, 27) .. "..."
    end

    local tab_handle = tabnr_to_handle(i)
    local highlight = get_tab_highlight(i, current_tab, tab_handle)

    -- %{i}T marks the clickable region for tab i (enables mouse/touch tap)
    local marker = i == current_tab and '◆ ' or '  '
    table.insert(result, string.format('%%%dT%s %s%d:%s %%T ', i, highlight, marker, i, title))
  end

  table.insert(result, '%#TabLineFill#%T')

  return table.concat(result)
end

-- Setup function
function M.setup()
  if vim.o.showtabline < 2 then
    vim.o.showtabline = 2
  end

  -- Enable mouse in all modes so touch/click on tabline works
  if not vim.o.mouse:find('a') then
    vim.o.mouse = 'a'
  end

  vim.cmd([[
    function! TabLine()
      return luaeval('_G.tab_titles.tabline()')
    endfunction
  ]])

  vim.o.tabline = '%!TabLine()'

  vim.api.nvim_create_autocmd('TabEnter', {
    callback = function()
      local handle = vim.api.nvim_get_current_tabpage()
      last_focused[handle] = os.time()
    end,
  })

  vim.api.nvim_create_autocmd({'TabEnter', 'TabNew', 'BufEnter', 'TermOpen'}, {
    pattern = '*',
    callback = function()
      M.update_all_tab_titles()
    end
  })

  vim.api.nvim_create_autocmd('TabClosed', {
    callback = function()
      local valid = {}
      for _, h in ipairs(vim.api.nvim_list_tabpages()) do
        valid[h] = true
      end
      for h in pairs(custom_tab_names) do
        if not valid[h] then
          custom_tab_names[h] = nil
        end
      end
      for h in pairs(last_focused) do
        if not valid[h] then
          last_focused[h] = nil
        end
      end
    end
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    callback = function()
      setup_dim_highlights()
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    callback = function(ev)
      custom_buf_names[ev.buf] = nil
    end
  })

  vim.api.nvim_create_user_command('TabRename', function(opts)
    M.set_tab_name(vim.fn.tabpagenr(), opts.args)
  end, { nargs = '*', desc = 'Set a custom name for the current tab' })

  vim.keymap.set('n', '<leader>tabrn', function()
    local tabnr = vim.fn.tabpagenr()
    local handle = tabnr_to_handle(tabnr)
    local current = (handle and custom_tab_names[handle]) or ""
    local new_name = vim.fn.input('Tab name: ', current)
    M.set_tab_name(tabnr, new_name)
  end, { silent = true, desc = 'Rename current tab' })

  setup_dim_highlights()
end

_G.tab_titles = M

M.setup()

return M
