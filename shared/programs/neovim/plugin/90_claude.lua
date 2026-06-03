-- Claude Code floating window and terminal
local ClaudeCode = {}

ClaudeCode.win = nil
ClaudeCode.buf = nil

-- Scan terminal buffer lines (bottom-up) for a Claude session UUID
local function find_session_in_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local line_count = vim.api.nvim_buf_line_count(buf)
  local start = math.max(0, line_count - 50)
  local lines = vim.api.nvim_buf_get_lines(buf, start, line_count, false)
  for i = #lines, 1, -1 do
    local uuid = lines[i]:match(
      "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
    )
    if uuid then return uuid end
  end
  return nil
end

-- Set up session UUID detection for a Claude terminal buffer.
-- Fires 30 initial 1s polls, then installs a TermEnter autocmd for indefinite retry.
local function setup_claude_session_watcher(buf)
  local function try_update()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local session_id = find_session_in_buf(buf)
    if session_id and vim.b[buf].terminal_session_id ~= session_id then
      vim.b[buf].terminal_session_id = session_id
      if _G.tab_titles then _G.tab_titles.update_all_tab_titles() end
    end
  end

  for i = 1, 30 do
    vim.defer_fn(try_update, i * 1000)
  end

  vim.api.nvim_create_autocmd("TermEnter", {
    buffer = buf,
    callback = try_update,
  })
end

local UUID_PAT = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local function is_claude_session_id(s)
  return s ~= nil and s:match(UUID_PAT) ~= nil
end

-- List Claude session IDs from ~/.claude/projects/ (most recent first)
local function list_claude_sessions()
  local home = vim.fn.expand("~")
  local cmd = string.format(
    'find "%s/.claude/projects" -maxdepth 2 -name "*.jsonl" -exec basename "{}" .jsonl \\; 2>/dev/null'
      .. ' | grep -E "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" | sort -r',
    home
  )
  local handle = io.popen(cmd)
  local sessions = {}
  if handle then
    for line in handle:lines() do
      table.insert(sessions, line)
    end
    handle:close()
  end
  return sessions
end

-- Look up the working directory recorded in a Claude session's .jsonl file.
local function work_dir_from_claude_session(session_id)
  local home = vim.fn.expand("~")
  local cmd = string.format(
    'find "%s/.claude/projects" -name "%s.jsonl" 2>/dev/null | head -1',
    home, session_id
  )
  local handle = io.popen(cmd)
  if not handle then return nil end
  local jsonl_path = handle:read("*l")
  handle:close()
  if not jsonl_path or jsonl_path == '' then return nil end

  local f = io.open(jsonl_path, "r")
  if not f then return nil end
  local cwd = nil
  for _ = 1, 10 do
    local line = f:read("*l")
    if not line then break end
    local dir = line:match('"cwd":"([^"]+)"')
    if dir then cwd = dir; break end
  end
  f:close()
  return cwd and vim.fn.isdirectory(cwd) == 1 and cwd or nil
end

-- Custom completion:
--   arg 1 – session IDs by default; directories if arglead starts with / ~ .
--   arg 2 – session IDs (when arg 1 was a directory)
local function claude_complete(arglead, cmdline, cursorpos)
  local before = cmdline:sub(1, cursorpos)
  local n = 0
  for _ in before:gmatch('%S+') do n = n + 1 end
  local arg_pos = n - 1 + (before:match('%s$') and 1 or 0)

  if arg_pos <= 1 then
    if arglead:match('^[/%.~]') then
      return vim.fn.getcompletion(arglead, 'dir')
    end
    local sessions = list_claude_sessions()
    if arglead == '' then return sessions end
    return vim.tbl_filter(function(s) return vim.startswith(s, arglead) end, sessions)
  else
    local sessions = list_claude_sessions()
    if arglead == '' then return sessions end
    return vim.tbl_filter(function(s) return vim.startswith(s, arglead) end, sessions)
  end
end

-- Parse command args into (work_dir, session_id), auto-deriving work_dir from
-- the session when a UUID is given as the sole first argument.
local function parse_claude_args(fargs)
  local arg1 = fargs[1]
  local arg2 = fargs[2]
  local work_dir, session_id

  if arg1 and is_claude_session_id(arg1) then
    session_id = arg1
    work_dir = work_dir_from_claude_session(session_id)
  else
    work_dir = (arg1 and arg1 ~= '') and arg1 or nil
    session_id = (arg2 and arg2 ~= '') and arg2 or nil
    if session_id and not work_dir then
      work_dir = work_dir_from_claude_session(session_id)
    end
  end

  return work_dir, session_id
end

-- Common function to create claude command
local function get_claude_cmd(work_dir, session_id)
  -- Ask user for permission mode
  local choice = vim.fn.confirm(
    'Select permission mode for Claude Code:',
    "&Default\n&Bypass Permissions\nDon't As&k\n&Accept Edits\n&Cancel",
    1  -- Default to "Default"
  )

  -- Cancel option (choice == 5 or 0)
  if choice == 5 or choice == 0 then
    return nil
  end

  local permission_mode = ''
  if choice == 2 then
    permission_mode = ' --permission-mode bypassPermissions'
  elseif choice == 3 then
    permission_mode = ' --permission-mode dontAsk'
  elseif choice == 4 then
    permission_mode = ' --permission-mode acceptEdits'
  end

  local cmd = 'eval "$(direnv export bash)" && claude' .. permission_mode

  if session_id and session_id ~= '' then
    cmd = cmd .. ' --resume ' .. vim.fn.shellescape(session_id)
  end

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
  pcall(function()
    vim.opt.cellwidths = {
      { 0x2500, 0x257f, 1 },
      { 0x2100, 0x214d, 1 },
    }
  end)
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

function ClaudeCode.toggle(work_dir, session_id)
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
    local cmd = get_claude_cmd(work_dir, session_id)

    -- If user cancelled, close the window and return
    if not cmd then
      if ClaudeCode.win and vim.api.nvim_win_is_valid(ClaudeCode.win) then
        vim.api.nvim_win_close(ClaudeCode.win, true)
        ClaudeCode.win = nil
      end
      return
    end

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
function ClaudeCode.open_in_terminal(work_dir, session_id)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_claude_cmd(work_dir, session_id)

  -- If user cancelled, return without opening terminal
  if not cmd then
    return
  end

  vim.cmd('enew')
  local buf = vim.api.nvim_get_current_buf()

  -- Set terminal metadata for tab title display
  local cwd = work_dir or vim.fn.getcwd()
  vim.b[buf].terminal_type = 'claude'
  vim.b[buf].terminal_cwd = cwd

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
  setup_claude_session_watcher(buf)

  vim.cmd('startinsert')

  vim.schedule(function()
    if _G.BottomTerminal then _G.BottomTerminal.open(cwd) end
  end)
end

-- Open in new tab function
function ClaudeCode.open_in_new_tab(work_dir, session_id)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_claude_cmd(work_dir, session_id)

  -- If user cancelled, return without opening terminal
  if not cmd then
    return
  end

  vim.cmd('tabnew')
  local buf = vim.api.nvim_get_current_buf()

  -- Set terminal metadata for tab title display
  local cwd = work_dir or vim.fn.getcwd()
  vim.b[buf].terminal_type = 'claude'
  vim.b[buf].terminal_cwd = cwd

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
  setup_claude_session_watcher(buf)

  vim.cmd('startinsert')

  vim.schedule(function()
    if _G.BottomTerminal then _G.BottomTerminal.open(cwd) end
  end)
end

-- Find existing Claude Code tab and switch to it
function ClaudeCode.find_tab()
  local tab_count = vim.fn.tabpagenr('$')
  local claude_tab = nil

  for i = 1, tab_count do
    local tab_buffers = vim.fn.tabpagebuflist(i)
    for _, buf in ipairs(tab_buffers) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' then
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
end

-- Returns the current buffer's directory, falling back to Neovim's cwd.
-- This ensures the agent and its companion terminal start in the same place,
-- even when Claude resumes a session from a different directory internally.
local function current_work_dir()
  local p = vim.fn.expand('%:p:h')
  if p ~= '' and vim.fn.isdirectory(p) == 1 then return p end
  return vim.fn.getcwd()
end

-- Command and keymap
-- Arg forms:
--   :ClaudeCode                        → new session in cwd
--   :ClaudeCode <uuid>                 → resume session, work_dir auto-derived
--   :ClaudeCode /dir                   → new session in /dir
--   :ClaudeCode /dir <uuid>            → resume session in /dir
-- Tab completion: arg1 shows session IDs (or dirs if starts with / ~ .)
vim.api.nvim_create_user_command('ClaudeCode', function(opts)
  local work_dir, session_id = parse_claude_args(opts.fargs)
  ClaudeCode.toggle(work_dir, session_id)
end, { nargs = '*', complete = claude_complete })
vim.api.nvim_create_user_command('ClaudeCodeTerminal', function(opts)
  local work_dir, session_id = parse_claude_args(opts.fargs)
  ClaudeCode.open_in_terminal(work_dir, session_id)
end, { nargs = '*', complete = claude_complete })
vim.api.nvim_create_user_command('ClaudeCodeTab', function(opts)
  local work_dir, session_id = parse_claude_args(opts.fargs)
  ClaudeCode.open_in_new_tab(work_dir, session_id)
end, { nargs = '*', complete = claude_complete })
vim.keymap.set('n', '<leader>claude', function() ClaudeCode.toggle(current_work_dir()) end, { desc = 'Toggle Claude Code' })
vim.keymap.set('n', '<leader>clauden', function() ClaudeCode.open_in_terminal(current_work_dir()) end, { desc = 'Open Claude Code in terminal' })
vim.keymap.set('n', '<leader>claudet', function() ClaudeCode.open_in_new_tab(current_work_dir()) end, { desc = 'Open Claude Code in new tab' })
vim.keymap.set('n', '<leader>findc', function() ClaudeCode.find_tab() end, { desc = 'Find Claude Code tab' })
