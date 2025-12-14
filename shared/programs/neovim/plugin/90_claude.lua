-- Claude Code floating window and terminal
local ClaudeCode = {}

ClaudeCode.win = nil
ClaudeCode.buf = nil

-- Common function to create claude command
local function get_claude_cmd(work_dir)
  local cmd = 'eval "$(direnv export bash)" && claude'
  if work_dir then
    cmd = 'cd ' .. vim.fn.shellescape(work_dir) ..  ' && ' .. cmd
  end
  return cmd
end

-- Common function to save ambiwidth setting
local function save_ambiwidth()
  return vim.opt.ambiwidth:get()
end

-- Common function to apply cell width settings
local function apply_cell_settings()
  vim.opt.ambiwidth = "single"
  vim.fn.setcellwidths {
    { 0x2500, 0x257f, 1 },
    { 0x2100, 0x214d, 1 },
  }
end

-- Common function to setup autocmds for maintaining cell settings
local function setup_cell_autocmds(buf, saved_ambiwidth)
  vim.api.nvim_create_autocmd({"BufEnter", "WinEnter"}, {
    buffer = buf,
    callback = function()
      apply_cell_settings()
    end
  })
  
  vim.api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
    buffer = buf,
    callback = function()
      vim.opt.ambiwidth = saved_ambiwidth
    end
  })
end

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

  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()
  
  -- To avoid issues with cell widths in the floating window
  apply_cell_settings()
  
  -- Start claude if not already running
  if vim.bo[ClaudeCode.buf].buftype ~= 'terminal' then
    local cmd = get_claude_cmd(work_dir)
    vim.fn.termopen(cmd, {
      on_exit = function()
        -- Restore ambiwidth setting
        vim.opt.ambiwidth = saved_ambiwidth
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

  -- Set buffer-local autocmd to maintain settings while in this terminal
  setup_cell_autocmds(ClaudeCode.buf, saved_ambiwidth)

  -- Set up keymaps for the floating window
  local opts = { buffer = ClaudeCode.buf, silent = true }
  vim.keymap.set('n', '<ESC>', function() ClaudeCode.toggle() end, opts)
  vim.keymap.set('n', 'q', function() ClaudeCode.toggle() end, opts)
  vim.keymap.set('t', '<C-x>', function() ClaudeCode.toggle() end, opts)
end

-- Terminal mode function
function ClaudeCode.open_in_terminal(work_dir)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()
  
  local cmd = get_claude_cmd(work_dir)
  vim.cmd('enew')
  local buf = vim.api.nvim_get_current_buf()
  
  -- Apply settings after buffer creation but before terminal starts
  vim.schedule(function()
    apply_cell_settings()
  end)
  
  vim.fn.termopen(cmd, {
    on_exit = function()
      -- Restore ambiwidth setting when terminal exits
      vim.opt.ambiwidth = saved_ambiwidth
    end
  })
  
  -- Set buffer-local autocmd to maintain settings while in this terminal
  setup_cell_autocmds(buf, saved_ambiwidth)
  
  vim.cmd('startinsert')
end

-- Command and keymap
vim.api.nvim_create_user_command('ClaudeCode', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  ClaudeCode.toggle(work_dir)
end, { nargs = '?' })
vim.api.nvim_create_user_command('ClaudeCodeTerminal', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  ClaudeCode.open_in_terminal(work_dir)
end, { nargs = '?' })
vim.keymap.set('n', '<leader>claude', function() ClaudeCode.toggle() end, { desc = 'Toggle Claude Code' })
vim.keymap.set('n', '<leader>clauden', function() ClaudeCode.open_in_terminal() end, { desc = 'Open Claude Code in terminal' })
vim.keymap.set('n', '<leader>claudet', function()
  -- Find tab with ClaudeCode terminal
  local tab_count = vim.fn.tabpagenr('$')
  local claude_tab = nil

  for i = 1, tab_count do
    local tab_buffers = vim.fn.tabpagebuflist(i)
    for _, buf in ipairs(tab_buffers) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_option(buf, 'buftype') == 'terminal' then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name:match('claude') then
          claude_tab = i
          break
        end
      end
    end
    if claude_tab then
      break
    end
  end

  if claude_tab then
    vim.cmd('tabn ' .. claude_tab)
  else
    vim.api.nvim_echo({{'No running ClaudeCode terminal found.', 'WarningMsg'}}, false, {})
  end
end, { desc = 'Go to tab with Claude Code terminal' })
