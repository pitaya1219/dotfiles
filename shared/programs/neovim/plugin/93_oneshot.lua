-- Oneshot: single-shot AI prompts via vibe or claude, without opening an
-- interactive session. Results appear in a bottom split or vim.notify.
--
-- Commands:
--   :VibeOneshot [...]        / :'<,'>VibeOneshot        — vibe, default display
--   :VibeOneshotSplit [...]   / :'<,'>VibeOneshotSplit   — vibe, bottom split
--   :VibeOneshotNotify [...]  / :'<,'>VibeOneshotNotify  — vibe, notify
--   :ClaudeOneshot [...]      / :'<,'>ClaudeOneshot      — claude, default display
--   :ClaudeOneshotSplit [...]  / :'<,'>ClaudeOneshotSplit  — claude, bottom split
--   :ClaudeOneshotNotify [...] / :'<,'>ClaudeOneshotNotify — claude, notify
--   :OneshotDisplay {split|notify}                       — set default display

local Oneshot = {}

Oneshot.display = "split"
Oneshot.win = nil
Oneshot.buf = nil

local LABEL = { vibe = 'Vibe', claude = 'Claude' }

local function current_work_dir()
  local p = vim.fn.expand('%:p:h')
  if p ~= '' and vim.fn.isdirectory(p) == 1 then return p end
  return vim.fn.getcwd()
end

local function show_split(text)
  local lines = vim.split(text, '\n', { plain = true })

  if not (Oneshot.buf and vim.api.nvim_buf_is_valid(Oneshot.buf)) then
    Oneshot.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[Oneshot.buf].filetype = 'markdown'
  end
  vim.bo[Oneshot.buf].modifiable = true
  vim.api.nvim_buf_set_lines(Oneshot.buf, 0, -1, false, lines)
  vim.bo[Oneshot.buf].modifiable = false

  -- Window already open: update buffer silently without stealing focus
  if Oneshot.win and vim.api.nvim_win_is_valid(Oneshot.win) then
    return
  end

  -- Open as bottom split like q: (command-line window)
  local height = math.max(10, math.floor(vim.o.lines * 0.35))
  vim.cmd('botright ' .. height .. 'split')
  Oneshot.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(Oneshot.win, Oneshot.buf)

  vim.wo[Oneshot.win].wrap = true
  vim.wo[Oneshot.win].linebreak = true
  vim.wo[Oneshot.win].winfixheight = true

  local close = function()
    if Oneshot.win and vim.api.nvim_win_is_valid(Oneshot.win) then
      vim.api.nvim_win_close(Oneshot.win, true)
      Oneshot.win = nil
    end
  end

  local opts = { buffer = Oneshot.buf, silent = true, nowait = true }
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

-- Single global WinClosed handler avoids once=true re-registration issue
vim.api.nvim_create_autocmd('WinClosed', {
  callback = function(ev)
    if Oneshot.win and tonumber(ev.match) == Oneshot.win then
      Oneshot.win = nil
    end
  end,
})

local function show_notify(text, title)
  vim.notify(text, vim.log.levels.INFO, { title = title or 'Oneshot' })
end

local function build_cmd(work_dir, instruction, backend)
  local esc_dir = vim.fn.shellescape(work_dir)
  local esc_ins = vim.fn.shellescape(instruction)
  local direnv  = 'eval "$(direnv export bash 2>/dev/null)"'
  if backend == 'claude' then
    return string.format('cd %s && %s && claude -p %s < /dev/null', esc_dir, direnv, esc_ins)
  else
    return string.format('cd %s && %s && vibe -p %s < /dev/null', esc_dir, direnv, esc_ins)
  end
end

function Oneshot.run(instruction, display_mode, backend)
  if not instruction or instruction == '' then
    vim.notify('No instruction provided', vim.log.levels.WARN, { title = 'Oneshot' })
    return
  end

  local mode  = display_mode or Oneshot.display
  local label = LABEL[backend] or backend
  local work_dir = current_work_dir()
  local stdout_lines = {}
  local stderr_lines = {}

  vim.notify('Running oneshot (' .. backend .. ')…', vim.log.levels.INFO, { title = 'Oneshot' })

  vim.fn.jobstart(
    { 'bash', '-c', build_cmd(work_dir, instruction, backend) },
    {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= '' then table.insert(stdout_lines, line) end
          end
        end
      end,
      on_stderr = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= '' then table.insert(stderr_lines, line) end
          end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          local title = label .. ' Oneshot'
          local text
          if code ~= 0 then
            local err = table.concat(stderr_lines, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
            text = err ~= '' and err or (backend .. ' exited with code ' .. code)
          else
            text = table.concat(stdout_lines, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
            if text == '' then text = '(no output)' end
          end
          if mode == 'notify' then
            show_notify(text, title)
          else
            show_split(text)
          end
        end)
      end,
    }
  )
end

local function instruction_from(opts)
  if opts.range == 2 then
    local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
    return table.concat(lines, '\n')
  end
  return opts.args
end

-- Vibe commands
vim.api.nvim_create_user_command('VibeOneshot', function(opts)
  Oneshot.run(instruction_from(opts), nil, 'vibe')
end, { nargs = '*', range = true, desc = 'Oneshot prompt via vibe (default display)' })

vim.api.nvim_create_user_command('VibeOneshotSplit', function(opts)
  Oneshot.run(instruction_from(opts), 'split', 'vibe')
end, { nargs = '*', range = true, desc = 'Oneshot prompt via vibe (bottom split)' })

vim.api.nvim_create_user_command('VibeOneshotNotify', function(opts)
  Oneshot.run(instruction_from(opts), 'notify', 'vibe')
end, { nargs = '*', range = true, desc = 'Oneshot prompt via vibe (notify)' })

-- Claude commands
vim.api.nvim_create_user_command('ClaudeOneshot', function(opts)
  Oneshot.run(instruction_from(opts), nil, 'claude')
end, { nargs = '*', range = true, desc = 'Oneshot prompt via claude (default display)' })

vim.api.nvim_create_user_command('ClaudeOneshotSplit', function(opts)
  Oneshot.run(instruction_from(opts), 'split', 'claude')
end, { nargs = '*', range = true, desc = 'Oneshot prompt via claude (bottom split)' })

vim.api.nvim_create_user_command('ClaudeOneshotNotify', function(opts)
  Oneshot.run(instruction_from(opts), 'notify', 'claude')
end, { nargs = '*', range = true, desc = 'Oneshot prompt via claude (notify)' })

-- Shared display setting
vim.api.nvim_create_user_command('OneshotDisplay', function(opts)
  local mode = opts.args
  if mode == 'split' or mode == 'notify' then
    Oneshot.display = mode
    vim.notify('Oneshot display: ' .. mode, vim.log.levels.INFO, { title = 'Oneshot' })
  else
    vim.notify('Usage: OneshotDisplay {split|notify}', vim.log.levels.WARN, { title = 'Oneshot' })
  end
end, {
  nargs = 1,
  complete = function() return { 'split', 'notify' } end,
  desc = 'Set default oneshot display mode',
})
