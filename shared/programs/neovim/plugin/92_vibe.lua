-- Vibe floating window and terminal
local Vibe = {}

Vibe.win = nil
Vibe.buf = nil

-- Look up the working directory recorded in a vibe session's meta.json.
local function work_dir_from_vibe_session(session_id)
  local vibe_home = vim.env.VIBE_HOME or vim.fn.expand("~/.vibe")
  local agent_sessions = vim.fn.expand("~/agent-sessions")
  local cmd = string.format(
    'ls -dt "%s/.vibe/logs/session/session_"*/ "%s/logs/session/session_"*/ 2>/dev/null',
    agent_sessions, vibe_home
  )
  local handle = io.popen(cmd)
  if not handle then return nil end
  local target_dir = nil
  for line in handle:lines() do
    local sid = line:match("session_%d+_%d+_([0-9a-f]+)/?$")
    if sid == session_id then
      target_dir = line:match("^(.+/?)")
      break
    end
  end
  handle:close()
  if not target_dir then return nil end

  -- Normalise trailing slash
  if not target_dir:match("/$") then target_dir = target_dir .. "/" end
  local meta = io.open(target_dir .. "meta.json", "r")
  if not meta then return nil end
  local content = meta:read("*a")
  meta:close()

  local cwd = content:match('"cwd":"([^"]+)"')
              or content:match('"work_dir":"([^"]+)"')
              or content:match('"working_dir":"([^"]+)"')
  return cwd and vim.fn.isdirectory(cwd) == 1 and cwd or nil
end

local VIBE_SID_PAT = "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$"

local function is_vibe_session_id(s)
  return s ~= nil and s:match(VIBE_SID_PAT) ~= nil
end

-- Session ID tracking: each termopen() below tags its shell with a unique
-- AGENT_TAB_MARKER env var. Vibe's pre_tool/post_agent hooks (see
-- scripts/agent-session-tab-pointer.py) inherit that var and write the
-- authoritative session_id to a pointer file keyed by the marker — no need
-- to guess it from session-log mtimes or terminal output anymore. Marker/
-- pointer protocol lives in 89_agent_tab_pointer.lua (shared with 90_claude.lua).
local agent_tab_pointer = _G.agent_tab_pointer

-- Poll for the hook-written pointer file, then adopt its session_id.
-- Fires 10 initial 1s polls for fast detection (post_agent needs a first
-- turn to complete), then installs a TermEnter autocmd for indefinite retry.
local function setup_vibe_session_watcher(buf, marker)
  local function try_update()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    if vim.b[buf].terminal_session_id then return end
    local session_id = agent_tab_pointer.read_pointer(marker)
    if session_id then
      vim.b[buf].terminal_session_id = session_id
      if _G.tab_titles then _G.tab_titles.update_all_tab_titles() end
    end
  end

  for i = 1, 10 do
    vim.defer_fn(try_update, i * 1000)
  end

  vim.api.nvim_create_autocmd("TermEnter", {
    buffer = buf,
    callback = try_update,
  })
end

-- List Vibe session IDs from known session directories (most recent first)
local function list_vibe_sessions()
  local vibe_home = vim.env.VIBE_HOME or vim.fn.expand("~/.vibe")
  local agent_sessions = vim.fn.expand("~/agent-sessions")
  local cmd = string.format(
    'ls -dt "%s/.vibe/logs/session/session_"*/ "%s/logs/session/session_"*/ 2>/dev/null',
    agent_sessions, vibe_home
  )
  local handle = io.popen(cmd)
  local sessions = {}
  local seen = {}
  if handle then
    for line in handle:lines() do
      local sid = line:match("session_%d+_%d+_([0-9a-f]+)/?$")
      if sid and not seen[sid] then
        seen[sid] = true
        table.insert(sessions, sid)
      end
    end
    handle:close()
  end
  return sessions
end

-- Custom completion:
--   arg 1 – session IDs by default; directories if arglead starts with / ~ .
--   arg 2 – session IDs (when arg 1 was a directory)
local function vibe_complete(arglead, cmdline, cursorpos)
  local before = cmdline:sub(1, cursorpos)
  local n = 0
  for _ in before:gmatch('%S+') do n = n + 1 end
  local arg_pos = n - 1 + (before:match('%s$') and 1 or 0)

  if arg_pos <= 1 then
    if arglead:match('^[/%.~]') then
      return vim.fn.getcompletion(arglead, 'dir')
    end
    local sessions = list_vibe_sessions()
    if arglead == '' then return sessions end
    return vim.tbl_filter(function(s) return vim.startswith(s, arglead) end, sessions)
  else
    local sessions = list_vibe_sessions()
    if arglead == '' then return sessions end
    return vim.tbl_filter(function(s) return vim.startswith(s, arglead) end, sessions)
  end
end

-- Parse command args into (work_dir, session_id), auto-deriving work_dir from
-- the session when an 8-char hex session ID is given as the sole first argument.
local function parse_vibe_args(fargs)
  local arg1 = fargs[1]
  local arg2 = fargs[2]
  local work_dir, session_id

  if arg1 and is_vibe_session_id(arg1) then
    session_id = arg1
    work_dir = work_dir_from_vibe_session(session_id)
  else
    work_dir = (arg1 and arg1 ~= '') and arg1 or nil
    session_id = (arg2 and arg2 ~= '') and arg2 or nil
    if session_id and not work_dir then
      work_dir = work_dir_from_vibe_session(session_id)
    end
  end

  return work_dir, session_id
end

-- Common function to create vibe command
-- session_id: 8-char hex string to resume a specific session (vibe --resume <id>)
local function get_vibe_cmd(work_dir, session_id)
  -- Ask user for permission mode (same as Claude Code)
  local choice = vim.fn.confirm(
    'Select permission mode for Vibe:',
    "&Default\n&Auto-Approve\n&Cancel",
    1  -- Default to "Default"
  )

  -- Cancel option (choice == 3 or 0)
  if choice == 3 or choice == 0 then
    return nil
  end

  local permission_mode = ''
  if choice == 2 then
    -- Auto-Approve -> --auto-approve
    permission_mode = ' --auto-approve'
  end

  local cmd = 'eval "$(direnv export bash)" && vibe' .. permission_mode

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

function Vibe.toggle(work_dir, session_id)
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
    local cmd = get_vibe_cmd(work_dir, session_id)

    -- If user cancelled, close the window and return
    if not cmd then
      if Vibe.win and vim.api.nvim_win_is_valid(Vibe.win) then
        vim.api.nvim_win_close(Vibe.win, true)
        Vibe.win = nil
      end
      return
    end

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
function Vibe.open_in_terminal(work_dir, session_id)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_vibe_cmd(work_dir, session_id)

  -- If user cancelled, return without opening terminal
  if not cmd then
    return
  end

  vim.cmd('enew')
  local buf = vim.api.nvim_get_current_buf()

  -- Set terminal metadata for tab title display
  local cwd = work_dir or vim.fn.getcwd()
  vim.b[buf].terminal_type = 'vibe'
  vim.b[buf].terminal_cwd = cwd
  local marker = agent_tab_pointer.new_marker()

  -- Apply settings after buffer creation but before terminal starts
  vim.schedule(function()
    apply_cell_settings()
  end)

  vim.fn.termopen(cmd, {
    env = { AGENT_TAB_MARKER = marker },
    on_exit = function()
      -- Restore ambiwidth setting when terminal exits
      vim.opt.ambiwidth = saved_ambiwidth
    end
  })

  -- Set buffer-local autocmd to maintain settings while in this terminal
  setup_cell_autocmds(buf, saved_ambiwidth)
  setup_vibe_session_watcher(buf, marker)

  vim.cmd('startinsert')

  vim.schedule(function()
    if _G.BottomTerminal then _G.BottomTerminal.open(cwd) end
  end)
end

-- Open in new tab function
function Vibe.open_in_new_tab(work_dir, session_id)
  -- Save current ambiwidth setting
  local saved_ambiwidth = save_ambiwidth()

  local cmd = get_vibe_cmd(work_dir, session_id)

  -- If user cancelled, return without opening terminal
  if not cmd then
    return
  end

  vim.cmd('tabnew')
  local buf = vim.api.nvim_get_current_buf()

  -- Set terminal metadata for tab title display
  local cwd = work_dir or vim.fn.getcwd()
  vim.b[buf].terminal_type = 'vibe'
  vim.b[buf].terminal_cwd = cwd
  local marker = agent_tab_pointer.new_marker()

  -- Apply settings after buffer creation but before terminal starts
  vim.schedule(function()
    apply_cell_settings()
  end)

  vim.fn.termopen(cmd, {
    env = { AGENT_TAB_MARKER = marker },
    on_exit = function()
      -- Restore ambiwidth setting when terminal exits
      vim.opt.ambiwidth = saved_ambiwidth
    end
  })

  -- Set buffer-local autocmd to maintain settings while in this terminal
  setup_cell_autocmds(buf, saved_ambiwidth)
  setup_vibe_session_watcher(buf, marker)

  vim.cmd('startinsert')

  vim.schedule(function()
    if _G.BottomTerminal then _G.BottomTerminal.open(cwd) end
  end)
end

-- Find existing Vibe tab and switch to it
function Vibe.find_tab()
  local tab_count = vim.fn.tabpagenr('$')
  local vibe_tab = nil

  for i = 1, tab_count do
    local tab_buffers = vim.fn.tabpagebuflist(i)
    for _, buf in ipairs(tab_buffers) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' then
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

local function current_work_dir()
  local p = vim.fn.expand('%:p:h')
  if p ~= '' and vim.fn.isdirectory(p) == 1 then return p end
  return vim.fn.getcwd()
end

-- Command and keymap
-- Arg forms:
--   :Vibe                        → new session in cwd
--   :Vibe <8-hex-id>             → resume session, work_dir auto-derived
--   :Vibe /dir                   → new session in /dir
--   :Vibe /dir <8-hex-id>        → resume session in /dir
-- Tab completion: arg1 shows session IDs (or dirs if starts with / ~ .)
vim.api.nvim_create_user_command('Vibe', function(opts)
  local work_dir, session_id = parse_vibe_args(opts.fargs)
  Vibe.toggle(work_dir, session_id)
end, { nargs = '*', complete = vibe_complete })
vim.api.nvim_create_user_command('VibeTerminal', function(opts)
  local work_dir, session_id = parse_vibe_args(opts.fargs)
  Vibe.open_in_terminal(work_dir, session_id)
end, { nargs = '*', complete = vibe_complete })
vim.api.nvim_create_user_command('VibeTab', function(opts)
  local work_dir, session_id = parse_vibe_args(opts.fargs)
  Vibe.open_in_new_tab(work_dir, session_id)
end, { nargs = '*', complete = vibe_complete })
vim.keymap.set('n', '<leader>vibe', function() Vibe.toggle(current_work_dir()) end, { desc = 'Toggle Vibe' })
vim.keymap.set('n', '<leader>viben', function() Vibe.open_in_terminal(current_work_dir()) end, { desc = 'Open Vibe in terminal' })
vim.keymap.set('n', '<leader>vibet', function() Vibe.open_in_new_tab(current_work_dir()) end, { desc = 'Open Vibe in new tab' })
vim.keymap.set('n', '<leader>findv', function() Vibe.find_tab() end, { desc = 'Find Vibe tab' })
