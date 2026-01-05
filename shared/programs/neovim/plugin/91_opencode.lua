-- OpenCode floating window and terminal
local OpenCode = {}

OpenCode.win = nil
OpenCode.buf = nil

-- Common function to create opencode command
local function get_opencode_cmd(work_dir)
  local cmd = 'eval "$(direnv export bash)" && opencode'

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

function OpenCode.toggle(work_dir)
  if OpenCode.win and vim.api.nvim_win_is_valid(OpenCode.win) then
    vim.api.nvim_win_close(OpenCode.win, true)
    OpenCode.win = nil
    return
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer if it doesn't exist
  if not OpenCode.buf or not vim.api.nvim_buf_is_valid(OpenCode.buf) then
    OpenCode.buf = vim.api.nvim_create_buf(false, true)
  end

  OpenCode.win = vim.api.nvim_open_win(OpenCode.buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' OpenCode ',
    title_pos = 'center'
  })

  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  -- To avoid issues with cell widths in the floating window
  apply_cell_settings()

  -- Start opencode if not already running
  if vim.bo[OpenCode.buf].buftype ~= 'terminal' then
    local cmd = get_opencode_cmd(work_dir)

    vim.fn.termopen(cmd, {
      on_exit = function()
        -- Restore ambiwidth setting
        vim.opt.ambiwidth = saved_ambiwidth
        if OpenCode.buf and vim.api.nvim_buf_is_valid(OpenCode.buf) then
          vim.api.nvim_buf_delete(OpenCode.buf, { force = true })
          OpenCode.buf = nil
        end
        if OpenCode.win and vim.api.nvim_win_is_valid(OpenCode.win) then
          OpenCode.win = nil
        end
      end
    })
  end

  vim.cmd('startinsert')

  -- Set buffer-local autocmd to maintain settings while in this terminal
  setup_cell_autocmds(OpenCode.buf, saved_ambiwidth)

  -- Set up keymaps for the floating window
  local opts = { buffer = OpenCode.buf, silent = true }
  vim.keymap.set('n', '<ESC>', function() OpenCode.toggle() end, opts)
  vim.keymap.set('n', 'q', function() OpenCode.toggle() end, opts)
  vim.keymap.set('t', '<C-x>', function() OpenCode.toggle() end, opts)
end

-- Terminal mode function
function OpenCode.open_in_terminal(work_dir)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_opencode_cmd(work_dir)

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

-- Open in new tab function
function OpenCode.open_in_new_tab(work_dir)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_opencode_cmd(work_dir)

  vim.cmd('tabnew')
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

-- Find existing OpenCode tab and switch to it
function OpenCode.find_tab()
  local tab_count = vim.fn.tabpagenr('$')
  local opencode_tab = nil

  for i = 1, tab_count do
    local tab_buffers = vim.fn.tabpagebuflist(i)
    for _, buf in ipairs(tab_buffers) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_option(buf, 'buftype') == 'terminal' then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name:match('opencode') then
          opencode_tab = i
          break
        end
      end
    end
    if opencode_tab then
      break
    end
  end

  if opencode_tab then
    vim.cmd('tabn ' .. opencode_tab)
  else
    vim.api.nvim_echo({{'No running OpenCode terminal found.', 'WarningMsg'}}, false, {})
  end
end

-- Command and keymap
vim.api.nvim_create_user_command('OpenCode', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  OpenCode.toggle(work_dir)
end, { nargs = '?' })
vim.api.nvim_create_user_command('OpenCodeTerminal', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  OpenCode.open_in_terminal(work_dir)
end, { nargs = '?' })
vim.api.nvim_create_user_command('OpenCodeTab', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  OpenCode.open_in_new_tab(work_dir)
end, { nargs = '?' })
vim.keymap.set('n', '<leader>opencode', function() OpenCode.toggle() end, { desc = 'Toggle OpenCode' })
vim.keymap.set('n', '<leader>opencoden', function() OpenCode.open_in_terminal() end, { desc = 'Open OpenCode in terminal' })
vim.keymap.set('n', '<leader>opencodet', function() OpenCode.open_in_new_tab() end, { desc = 'Open OpenCode in new tab' })
vim.keymap.set('n', '<leader>findo', function() OpenCode.find_tab() end, { desc = 'Find OpenCode tab' })
