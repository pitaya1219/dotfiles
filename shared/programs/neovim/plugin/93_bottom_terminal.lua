-- Per-tab bottom terminal panel with show/hide toggle
local M = {}
_G.BottomTerminal = M

local state = {}  -- [tabnr] = { buf, win }

-- Highlight for the winbar notice (bold yellow; links to WarningMsg for theme compat)
vim.api.nvim_set_hl(0, 'BottomTermNotice', { link = 'WarningMsg', bold = true, default = true })

local NOTICE = '%#BottomTermNotice#  ⬇  terminal ready  ·  <Alt-j> to open  %*'

-- Update winbar on every window in the current tab.
-- Shows notice when bottom terminal is hidden, clears it when visible.
local function refresh_notice()
  local tab = vim.fn.tabpagenr()
  local s = state[tab]
  local is_hidden = s
    and vim.api.nvim_buf_is_valid(s.buf)
    and (not s.win or not vim.api.nvim_win_is_valid(s.win))

  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == '' then
      vim.wo[w].winbar = is_hidden and NOTICE or ''
    end
  end
end

vim.api.nvim_create_autocmd('TabClosed', {
  callback = function(ev)
    state[tonumber(ev.file)] = nil
  end,
})

-- Refresh notice whenever we switch tabs (other tabs may have hidden terminals)
vim.api.nvim_create_autocmd('TabEnter', {
  callback = function()
    vim.schedule(refresh_notice)
  end,
})

-- Start a hidden terminal buffer for the current tab.
-- The window is closed immediately; the shell process keeps running.
-- cwd: optional starting directory; defaults to Neovim's current working directory.
function M.open(cwd)
  local tab = vim.fn.tabpagenr()
  local s = state[tab]

  if s and vim.api.nvim_buf_is_valid(s.buf) then
    return
  end

  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd('noautocmd botright new')
  local buf = vim.api.nvim_get_current_buf()
  local term_opts = cwd and { cwd = cwd } or {}
  vim.fn.termopen(vim.env.SHELL or 'bash', term_opts)
  vim.api.nvim_win_close(0, false)

  state[tab] = { buf = buf, win = nil }
  vim.api.nvim_set_current_win(prev_win)
  vim.schedule(refresh_notice)
end

function M.toggle()
  local tab = vim.fn.tabpagenr()
  local s = state[tab]

  if not s or not vim.api.nvim_buf_is_valid(s.buf) then
    local cwd = vim.fn.getcwd()
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname ~= '' and vim.bo.buftype == '' then
      local dir = vim.fn.fnamemodify(bufname, ':p:h')
      if dir ~= '' and vim.fn.isdirectory(dir) == 1 then cwd = dir end
    end
    M.open(cwd)
    s = state[tab]
    if not s then return end
  end

  if s.win and vim.api.nvim_win_is_valid(s.win) then
    -- Visible → hide
    vim.api.nvim_win_close(s.win, false)
    s.win = nil
    refresh_notice()
    vim.schedule(function()
      local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      if vim.bo[buf].buftype == 'terminal' then
        vim.cmd('startinsert')
      end
    end)
  else
    -- Hidden → show maximized at bottom
    vim.cmd('botright sbuffer ' .. s.buf)
    s.win = vim.api.nvim_get_current_win()
    vim.cmd('wincmd _')
    vim.cmd('redraw!')
    refresh_notice()
    vim.cmd('startinsert')
  end
end

-- <M-j> = Alt+j on Linux, Option+j on macOS when terminal sends Esc+j (e.g. iTerm2 with Use Option as Meta Key)
vim.keymap.set({ 'n', 't' }, '<M-j>', M.toggle, { desc = 'Toggle bottom terminal' })
-- macOS fallback: Option+j sends ∆ (U+2206) in Terminal.app and other apps that don't remap Option as Meta
vim.keymap.set({ 'n', 't' }, '∆', M.toggle, { desc = 'Toggle bottom terminal (macOS)' })
