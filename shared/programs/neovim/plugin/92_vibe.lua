-- Vibe floating window and terminal
local Vibe = {}

Vibe.win = nil
Vibe.buf = nil

-- Common function to create vibe command
local function get_vibe_cmd(work_dir)
  local cmd = 'eval "$(direnv export bash)" && vibe'

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

function Vibe.toggle(work_dir)
  if Vibe.win and vim.api.nvim_win_is_valid(Vibe.win) then
    vim.api.nvim_win_close(Vibe.win, true)
    Vibe.win = nil
    return
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer if it doesn't exist
  if not Vibe.buf or not vim.api.nvim_buf_is_valid(Vibe.buf) then
    Vibe.buf = vim.api.nvim_create_buf(false, true)
  end

  Vibe.win = vim.api.nvim_open_win(Vibe.buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Vibe ',
    title_pos = 'center'
  })

  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  -- To avoid issues with cell widths in the floating window
  apply_cell_settings()

  -- Start vibe if not already running
  if vim.bo[Vibe.buf].buftype ~= 'terminal' then
    local cmd = get_vibe_cmd(work_dir)

    vim.fn.termopen(cmd, {
      on_exit = function()
        -- Restore ambiwidth setting
        vim.opt.ambiwidth = saved_ambiwidth
        if Vibe.buf and vim.api.nvim_buf_is_valid(Vibe.buf) then
          vim.api.nvim_buf_delete(Vibe.buf, { force = true })
          Vibe.buf = nil
        end
        if Vibe.win and vim.api.nvim_win_is_valid(Vibe.win) then
          Vibe.win = nil
        end
      end
    })
  end

  vim.cmd('startinsert')

  -- Set buffer-local autocmd to maintain settings while in this terminal
  setup_cell_autocmds(Vibe.buf, saved_ambiwidth)

  -- Set up keymaps for the floating window
  local opts = { buffer = Vibe.buf, silent = true }
  vim.keymap.set('n', '<ESC>', function() Vibe.toggle() end, opts)
  vim.keymap.set('n', 'q', function() Vibe.toggle() end, opts)
  vim.keymap.set('t', '<C-x>', function() Vibe.toggle() end, opts)
end

-- Terminal mode function
function Vibe.open_in_terminal(work_dir)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_vibe_cmd(work_dir)

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
function Vibe.open_in_new_tab(work_dir)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_vibe_cmd(work_dir)

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

-- Find existing Vibe tab and switch to it
function Vibe.find_tab()
  local tab_count = vim.fn.tabpagenr('$')
  local vibe_tab = nil

  for i = 1, tab_count do
    local tab_buffers = vim.fn.tabpagebuflist(i)
    for _, buf in ipairs(tab_buffers) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_option(buf, 'buftype') == 'terminal' then
        -- Check if this terminal is running the vibe command
        local is_vibe_tab = false
        
        -- Try to get the terminal job command
        local job_id = vim.fn.jobstart('echo', { rpc = true })
        if job_id and job_id > 0 then
          -- Simple heuristic: check if buffer contains vibe-related content
          local lines = vim.api.nvim_buf_get_lines(buf, 0, 5, false)
          for _, line in ipairs(lines) do
            if line:lower():match('vibe') or line:match('mistral') then
              is_vibe_tab = true
              break
            end
          end
        end
        
        -- Also check buffer name as fallback
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name:match('vibe') or buf_name:match('mistral') then
          is_vibe_tab = true
        end
        
        if is_vibe_tab then
          vibe_tab = i
          break
        end
      end
    end
    if vibe_tab then
      break
    end
  end

  if vibe_tab then
    vim.cmd('tabn ' .. vibe_tab)
  else
    vim.api.nvim_echo({{'No running Vibe terminal found.', 'WarningMsg'}}, false, {})
  end
end

-- Command and keymap
vim.api.nvim_create_user_command('Vibe', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  Vibe.toggle(work_dir)
end, { nargs = '?' })
vim.api.nvim_create_user_command('VibeTerminal', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  Vibe.open_in_terminal(work_dir)
end, { nargs = '?' })
vim.api.nvim_create_user_command('VibeTab', function(opts)
  local work_dir = opts.args ~= '' and opts.args or nil
  Vibe.open_in_new_tab(work_dir)
end, { nargs = '?' })
vim.keymap.set('n', '<leader>vibe', function() Vibe.toggle() end, { desc = 'Toggle Vibe' })
vim.keymap.set('n', '<leader>viben', function() Vibe.open_in_terminal() end, { desc = 'Open Vibe in terminal' })
vim.keymap.set('n', '<leader>vibet', function() Vibe.open_in_new_tab() end, { desc = 'Open Vibe in new tab' })
vim.keymap.set('n', '<leader>findv', function() Vibe.find_tab() end, { desc = 'Find Vibe tab' })
