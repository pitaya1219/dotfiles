-- Session management: CWD-based auto-sessions + named global sessions
--
-- Storage layout:
--   stdpath('data')/sessions/<escaped-cwd>.vim   -- CWD sessions (auto)
--   stdpath('data')/sessions/named/<name>.vim    -- named sessions (manual)
--
-- Commands:
--   :SessionSave [name]     no name → CWD session; name → named session
--   :SessionRestore [name]  no name → CWD session; name → named session
--   :SessionDelete [name]   no name → CWD session; name → named session
--   :SessionList            floating picker for named sessions
--
-- Keymaps:
--   <leader>sess   save CWD session
--   <leader>sesr   restore CWD session
--   <leader>sesd   delete CWD session
--   <leader>sesS   save named session (prompts for name)
--   <leader>sesl   named session picker (list / restore / delete)

local session_dir = vim.fn.stdpath('data') .. '/sessions'
local named_dir   = session_dir .. '/named'

vim.opt.sessionoptions = { 'buffers', 'curdir', 'tabpages', 'winsize', 'folds' }

-- ─── internal helpers ────────────────────────────────────────────────────────

local function escape_name(s)
  return s:gsub('[/\\:*?"<>|%s]', '_')
end

local function cwd_file()
  return session_dir .. '/' .. escape_name(vim.fn.getcwd()) .. '.vim'
end

local function named_file(name)
  return named_dir .. '/' .. escape_name(name) .. '.vim'
end

local function has_real_files()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_get_option(buf, 'buflisted')
      and vim.bo[buf].buftype == ''
      and vim.api.nvim_buf_get_name(buf) ~= '' then
      return true
    end
  end
  return false
end

local function hide_terminal_bufs()
  local hidden = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' then
      vim.api.nvim_buf_set_option(buf, 'buflisted', false)
      table.insert(hidden, buf)
    end
  end
  return hidden
end

local function restore_listed(bufs)
  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_option(buf, 'buflisted', true)
    end
  end
end

local function do_save(path, dir)
  vim.fn.mkdir(dir or session_dir, 'p')
  local hidden = hide_terminal_bufs()
  local ok, err = pcall(vim.cmd, 'mksession! ' .. vim.fn.fnameescape(path))
  restore_listed(hidden)
  return ok, err
end

local function do_restore(path)
  return pcall(vim.cmd, 'source ' .. vim.fn.fnameescape(path))
end

local function named_session_names(arglead)
  local files = vim.fn.glob(named_dir .. '/*.vim', false, true)
  local names = {}
  for _, f in ipairs(files) do
    local name = vim.fn.fnamemodify(f, ':t:r')
    if arglead == '' or name:find(arglead, 1, true) then
      table.insert(names, name)
    end
  end
  return names
end

-- ─── CWD sessions ────────────────────────────────────────────────────────────

local function save_cwd()
  if not has_real_files() then
    vim.notify('Session: no files to save.', vim.log.levels.WARN)
    return
  end
  local ok, err = do_save(cwd_file())
  if ok then
    vim.notify('Session saved (cwd).', vim.log.levels.INFO)
  else
    vim.notify('Session save failed: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

local function restore_cwd()
  local path = cwd_file()
  if vim.fn.filereadable(path) == 0 then
    vim.notify('Session: no saved session for this directory.', vim.log.levels.WARN)
    return
  end
  local ok, err = do_restore(path)
  if ok then
    vim.notify('Session restored (cwd).', vim.log.levels.INFO)
  else
    vim.notify('Session restore failed: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

local function delete_cwd()
  local path = cwd_file()
  if vim.fn.filereadable(path) == 0 then
    vim.notify('Session: no saved session for this directory.', vim.log.levels.WARN)
    return
  end
  vim.fn.delete(path)
  vim.notify('Session deleted (cwd).', vim.log.levels.INFO)
end

-- ─── named sessions ──────────────────────────────────────────────────────────

local function save_named(name)
  if not name or name == '' then
    name = vim.fn.input('Session name: ')
    if not name or name == '' then return end
  end
  local ok, err = do_save(named_file(name), named_dir)
  if ok then
    vim.notify('Session "' .. name .. '" saved.', vim.log.levels.INFO)
  else
    vim.notify('Session save failed: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

local function restore_named(name)
  local path = named_file(name)
  if vim.fn.filereadable(path) == 0 then
    vim.notify('Session "' .. name .. '" not found.', vim.log.levels.WARN)
    return
  end
  local ok, err = do_restore(path)
  if ok then
    vim.notify('Session "' .. name .. '" restored.', vim.log.levels.INFO)
  else
    vim.notify('Session restore failed: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

local function delete_named(name)
  local path = named_file(name)
  if vim.fn.filereadable(path) == 0 then
    vim.notify('Session "' .. name .. '" not found.', vim.log.levels.WARN)
    return
  end
  vim.fn.delete(path)
  vim.notify('Session "' .. name .. '" deleted.', vim.log.levels.INFO)
end

-- ─── session picker (CWD + named) ───────────────────────────────────────────

local function get_all_session_entries()
  local entries = {}
  local named_files = vim.fn.glob(named_dir .. '/*.vim', false, true)
  for _, f in ipairs(named_files) do
    local name = vim.fn.fnamemodify(f, ':t:r')
    table.insert(entries, { label = '[named] ' .. name, path = f })
  end
  local cwd_files = vim.fn.glob(session_dir .. '/*.vim', false, true)
  for _, f in ipairs(cwd_files) do
    local display = vim.fn.fnamemodify(f, ':t:r'):gsub('_', '/')
    table.insert(entries, { label = '[cwd]   ' .. display, path = f })
  end
  return entries
end

local function pick_session()
  local entries = get_all_session_entries()
  if #entries == 0 then
    vim.notify('Session: no sessions saved.', vim.log.levels.INFO)
    return
  end

  local current_idx = 1
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.max(50, math.floor(vim.o.columns * 0.5))
  local height = math.min(#entries + 2, 15)
  local win = vim.api.nvim_open_win(buf, true, {
    relative    = 'editor',
    width       = width,
    height      = height,
    col         = (vim.o.columns - width) / 2,
    row         = (vim.o.lines - height) / 2,
    style       = 'minimal',
    border      = 'rounded',
    title       = ' Sessions ',
    title_pos   = 'center',
    zindex      = 100,
  })

  local function update_display()
    local lines = {}
    for i, e in ipairs(entries) do
      table.insert(lines, (i == current_idx and '> ' or '  ') .. e.label)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { current_idx, 0 })
    end
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  vim.keymap.set('n', 'j', function()
    current_idx = math.min(current_idx + 1, #entries)
    update_display()
  end, { buffer = buf })

  vim.keymap.set('n', 'k', function()
    current_idx = math.max(current_idx - 1, 1)
    update_display()
  end, { buffer = buf })

  vim.keymap.set('n', 'g', function()
    current_idx = 1
    update_display()
  end, { buffer = buf })

  vim.keymap.set('n', 'G', function()
    current_idx = #entries
    update_display()
  end, { buffer = buf })

  vim.keymap.set('n', '<CR>', function()
    local entry = entries[current_idx]
    close()
    if entry then
      local ok, err = do_restore(entry.path)
      if ok then
        vim.notify('Session restored: ' .. entry.label:gsub('^[>%s]+', ''), vim.log.levels.INFO)
      else
        vim.notify('Session restore failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end, { buffer = buf })

  vim.keymap.set('n', 'd', function()
    local entry = entries[current_idx]
    if not entry then return end
    vim.fn.delete(entry.path)
    local label = entry.label
    table.remove(entries, current_idx)
    if #entries == 0 then
      close()
      vim.notify('Session deleted: ' .. label, vim.log.levels.INFO)
      return
    end
    if current_idx > #entries then current_idx = #entries end
    update_display()
    vim.notify('Session deleted: ' .. label, vim.log.levels.INFO)
  end, { buffer = buf })

  vim.keymap.set('n', 'q',     close, { buffer = buf })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf })

  update_display()
end

-- ─── user commands ───────────────────────────────────────────────────────────

vim.api.nvim_create_user_command('SessionSave', function(opts)
  if opts.args == '' then save_cwd() else save_named(opts.args) end
end, { nargs = '?', desc = 'Save session (no arg: cwd, name: named)' })

vim.api.nvim_create_user_command('SessionRestore', function(opts)
  if opts.args == '' then restore_cwd() else restore_named(opts.args) end
end, {
  nargs    = '?',
  desc     = 'Restore session (no arg: cwd, name: named)',
  complete = function(arglead) return named_session_names(arglead) end,
})

vim.api.nvim_create_user_command('SessionDelete', function(opts)
  if opts.args == '' then delete_cwd() else delete_named(opts.args) end
end, {
  nargs    = '?',
  desc     = 'Delete session (no arg: cwd, name: named)',
  complete = function(arglead) return named_session_names(arglead) end,
})

vim.api.nvim_create_user_command('SessionList', function()
  pick_session()
end, { desc = 'Open session picker (CWD + named)' })

-- ─── auto save / restore ─────────────────────────────────────────────────────

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    if has_real_files() then
      do_save(cwd_file())
    end
  end,
})

vim.api.nvim_create_autocmd('VimEnter', {
  nested = true,
  callback = function()
    if vim.fn.argc() == 0 then
      local path = cwd_file()
      if vim.fn.filereadable(path) == 1 then
        pcall(vim.cmd, 'source ' .. vim.fn.fnameescape(path))
      end
    end
  end,
})

-- ─── keymaps ─────────────────────────────────────────────────────────────────

vim.keymap.set('n', '<leader>sess', save_cwd,          { silent = true, desc = 'Save CWD session' })
vim.keymap.set('n', '<leader>sesr', restore_cwd,       { silent = true, desc = 'Restore CWD session' })
vim.keymap.set('n', '<leader>sesd', delete_cwd,        { silent = true, desc = 'Delete CWD session' })
vim.keymap.set('n', '<leader>sesS', save_named,        { silent = true, desc = 'Save named session (prompt)' })
vim.keymap.set('n', '<leader>sesl', pick_session,       { silent = true, desc = 'Session picker (CWD + named)' })
