-- Per-tab bottom terminal panel with show/hide toggle
local M = {}
_G.BottomTerminal = M

local state = {}  -- [tabnr] = { buf, win }

vim.api.nvim_create_autocmd("TabClosed", {
  callback = function(ev)
    state[tonumber(ev.file)] = nil
  end,
})

-- Start a hidden terminal buffer for the current tab.
-- The window is closed immediately; the shell process keeps running.
function M.open()
  local tab = vim.fn.tabpagenr()
  local s = state[tab]

  if s and vim.api.nvim_buf_is_valid(s.buf) then
    return
  end

  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd('noautocmd botright new')
  local buf = vim.api.nvim_get_current_buf()
  vim.fn.termopen(vim.env.SHELL or 'bash')
  vim.api.nvim_win_close(0, false)

  state[tab] = { buf = buf, win = nil }
  vim.api.nvim_set_current_win(prev_win)
end

function M.toggle()
  local tab = vim.fn.tabpagenr()
  local s = state[tab]

  if not s or not vim.api.nvim_buf_is_valid(s.buf) then
    M.open()
    s = state[tab]
    if not s then return end
  end

  if s.win and vim.api.nvim_win_is_valid(s.win) then
    -- Visible → hide
    vim.api.nvim_win_close(s.win, false)
    s.win = nil
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
    vim.cmd('startinsert')
  end
end

-- <M-j> = Alt+j on Linux, Option+j on macOS (terminal must send escape sequences for Option)
vim.keymap.set({ 'n', 't' }, '<M-j>', M.toggle, { desc = 'Toggle bottom terminal' })
