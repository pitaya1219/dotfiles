-- Claude Code floating window
local ClaudeCode = {}

ClaudeCode.win = nil
ClaudeCode.buf = nil

function ClaudeCode.toggle(work_dir)
  if ClaudeCode.win and vim.api.nvim_win_is_valid(ClaudeCode.win) then
    vim.api.nvim_win_close(ClaudeCode.win, true)
    ClaudeCode.win = nil
    return
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer if it doesn't exist
  if not ClaudeCode.buf or not vim.api.nvim_buf_is_valid(ClaudeCode.buf) then
    ClaudeCode.buf = vim.api.nvim_create_buf(false, true)
  end

  ClaudeCode.win = vim.api.nvim_open_win(ClaudeCode.buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Claude Code ',
    title_pos = 'center'
  })

  -- To avoid issues with cell widths in the floating window
  vim.fn.setcellwidths {
    { 0x2500, 0x257f, 1 },
    { 0x2100, 0x214d, 1 },
  }
  -- Start claude if not already running
  if vim.bo[ClaudeCode.buf].buftype ~= 'terminal' then
    local cmd = 'claude'
    if work_dir then
      cmd = 'cd ' .. vim.fn.shellescape(work_dir) .. ' && claude'
    end
    vim.fn.termopen(cmd, {
      on_exit = function()
        if ClaudeCode.buf and vim.api.nvim_buf_is_valid(ClaudeCode.buf) then
          vim.api.nvim_buf_delete(ClaudeCode.buf, { force = true })
          ClaudeCode.buf = nil
        end
        if ClaudeCode.win and vim.api.nvim_win_is_valid(ClaudeCode.win) then
          ClaudeCode.win = nil
        end
      end
    })
  end

  vim.cmd('startinsert')

  -- Set up keymaps for the floating window
  local opts = { buffer = ClaudeCode.buf, silent = true }
  vim.keymap.set('n', '<ESC>', function() ClaudeCode.toggle() end, opts)
  vim.keymap.set('n', 'q', function() ClaudeCode.toggle() end, opts)
  vim.keymap.set('t', '<C-x>', function() ClaudeCode.toggle() end, opts)
end

-- Command and keymap
vim.api.nvim_create_user_command('ClaudeCode', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  ClaudeCode.toggle(work_dir)
end, { nargs = '?' })
vim.keymap.set('n', '<leader>claude', function() ClaudeCode.toggle() end, { desc = 'Toggle Claude Code' })
