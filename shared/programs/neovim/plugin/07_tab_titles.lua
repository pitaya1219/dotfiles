-- Dynamic tab title management for Neovim
-- Sets tab titles based on terminal type:
-- - bash terminal: current directory name
-- - claude code terminal: first 8 chars of Claude session UUID
-- - vibe terminal: first 8 chars of Vibe session UUID

local M = {}

-- Get the most recent Vibe session ID from logs
-- Check .vibe/logs/session/ (project-local) first,
-- then ${VIBE_HOME:-~/.vibe}/logs/session/ (global)
function M.get_vibe_session_id()
  if vim.env.VIBE_SESSION_ID and vim.env.VIBE_SESSION_ID ~= "" then
    return vim.env.VIBE_SESSION_ID
  end

  local function find_and_read_meta()
    local locations = {
      vim.fn.getcwd() .. "/.vibe/logs/session",
      vim.fn.expand("~/agent-sessions/.vibe/logs/session"),
    }

    for _, loc in ipairs(locations) do
      local cmd = string.format('ls -dt "%s"/session_*/meta.json 2>/dev/null | head -1', loc)
      local handle = io.popen(cmd)
      local path = handle:read("*l")
      handle:close()
      if path and path ~= "" then
        local file = io.open(path, "r")
        if file then
          local content = file:read("*a")
          file:close()
          local session_id = content:match('"session_id":"([^"]+)"')
          if session_id then
            return session_id
          end
        end
      end
    end
    return nil
  end

  local session_id = find_and_read_meta()
  if session_id then
    return session_id
  end

  local vibe_home = vim.env.VIBE_HOME or vim.fn.expand("~/.vibe")
  local cmd2 = string.format('ls -dt "%s/logs/session"/session_*/meta.json 2>/dev/null | head -1', vibe_home)
  local handle = io.popen(cmd2)
  local path = handle:read("*l")
  handle:close()
  if path and path ~= "" then
    local file = io.open(path, "r")
    if file then
      local content = file:read("*a")
      file:close()
      session_id = content:match('"session_id":"([^"]+)"')
      if session_id then
        return session_id
      end
    end
  end

  return "vibe-" .. vim.fn.getpid()
end

-- Get the Claude Code session ID for the given working directory.
-- Looks in ~/.claude/projects/{encoded-cwd}/ for the most recently modified
-- session file (UUID.jsonl or UUID/ directory), matching CLAUDE.md convention.
function M.get_claude_session_id(work_dir)
  local cwd = work_dir or vim.fn.getcwd()
  -- Encode path the same way Claude does: replace / with -
  local encoded = cwd:gsub("/", "-")
  local project_dir = vim.fn.expand("~/.claude/projects") .. "/" .. encoded

  -- Use ls -dt with UUID glob patterns to find most recent session
  local cmd = string.format(
    'ls -dt "%s"/????????-????-????-????-????????????.jsonl "%s"/????????-????-????-????-????????????/ 2>/dev/null | head -1',
    project_dir, project_dir
  )
  local handle = io.popen(cmd)
  local path = handle:read("*l")
  handle:close()

  if path and path ~= "" then
    -- Extract UUID: strip .jsonl extension (files) or trailing slash (dirs)
    local session_id = path:match("([0-9a-f%-]+)%.jsonl$")
                    or path:match("([0-9a-f%-]+)/?$")
    if session_id then
      return session_id
    end
  end

  return "claude-" .. vim.fn.getpid()
end

-- Detect terminal type for a buffer
local function detect_terminal_type(buf)
  if vim.b[buf].terminal_type == 'vibe' then
    return 'vibe'
  end
  if vim.b[buf].terminal_type == 'claude' then
    return 'claude'
  end

  local buf_name = vim.api.nvim_buf_get_name(buf)
  if buf_name:match('vibe') or buf_name:match('mistral') then
    return 'vibe'
  end
  if buf_name:match('claude') then
    return 'claude'
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, 5, false)
  for _, line in ipairs(lines) do
    if line:lower():match('vibe') or line:lower():match('mistral') then
      return 'vibe'
    end
    if line:lower():match('claude') then
      return 'claude'
    end
  end

  return 'bash'
end

-- Get tab title for a specific tab
function M.get_tab_title(tabnr)
  local tab_buffers = vim.fn.tabpagebuflist(tabnr)
  local current_buf = tab_buffers[vim.fn.tabpagewinnr(tabnr)]

  if not vim.api.nvim_buf_is_valid(current_buf) then
    return ""
  end

  local buftype = vim.api.nvim_buf_get_option(current_buf, 'buftype')
  local buf_name = vim.api.nvim_buf_get_name(current_buf)

  if buftype == 'terminal' then
    local terminal_type = detect_terminal_type(current_buf)

    if terminal_type == 'vibe' then
      local session_id = vim.b[current_buf].terminal_session_id or M.get_vibe_session_id()
      if session_id then
        return tostring(session_id):sub(1, 8)
      end
      return "vibe"
    elseif terminal_type == 'claude' then
      local session_id = vim.b[current_buf].terminal_session_id
                      or M.get_claude_session_id(vim.b[current_buf].terminal_cwd)
      if session_id then
        return tostring(session_id):sub(1, 8)
      end
      return "claude"
    else
      local cwd
      if vim.b[current_buf].terminal_cwd then
        cwd = vim.b[current_buf].terminal_cwd
      else
        cwd = vim.fn.getcwd()
      end
      if cwd then
        local dir_name = cwd:match('([^/]+)$')
        if dir_name and dir_name ~= "" then
          return dir_name
        end
        return cwd
      end
      return "terminal"
    end
  end

  if buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":t")
  end

  return "[No Name]"
end

-- Update all tab titles
function M.update_all_tab_titles()
  local tab_count = vim.fn.tabpagenr('$')
  for i = 1, tab_count do
    local title = M.get_tab_title(i)
    vim.api.nvim_tabpage_set_var(i, 'tab_title', title)
  end
end

-- Custom tabline function
function M.tabline()
  local result = {}
  local tab_count = vim.fn.tabpagenr('$')
  local current_tab = vim.fn.tabpagenr()

  for i = 1, tab_count do
    local title = M.get_tab_title(i)

    if #title > 30 then
      title = title:sub(1, 27) .. "..."
    end

    local highlight
    if i == current_tab then
      highlight = '%#TabLineSel#'
    else
      highlight = '%#TabLine#'
    end

    table.insert(result, string.format('%s %d:%s %s ', highlight, i, title, highlight))
  end

  table.insert(result, '%#TabLineFill#%T')

  return table.concat(result)
end

-- Setup function
function M.setup()
  if vim.o.showtabline < 2 then
    vim.o.showtabline = 2
  end

  vim.cmd([[
    function! TabLine()
      return luaeval('_G.tab_titles.tabline()')
    endfunction
  ]])

  vim.o.tabline = '%!TabLine()'

  vim.api.nvim_create_autocmd({'TabEnter', 'TabNew', 'BufEnter', 'TermOpen'}, {
    pattern = '*',
    callback = function()
      M.update_all_tab_titles()
    end
  })
end

_G.tab_titles = M

M.setup()

return M
