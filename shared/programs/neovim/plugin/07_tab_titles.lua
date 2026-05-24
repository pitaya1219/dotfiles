-- Dynamic tab title management for Neovim
-- Sets tab titles based on terminal type:
-- - bash terminal: current directory name
-- - claude code terminal: claude-<pid>
-- - mistral vibe terminal: session ID from .vibe/logs/session/

local M = {}

-- Get the most recent Vibe session ID from logs
-- Checks project-local .vibe/ first, then falls back to global VIBE_HOME
local function get_vibe_session_id()
  -- Try to read from meta.json files in .vibe/logs/session/
  local function read_session_id_from_meta(meta_path)
    local file = io.open(meta_path, "r")
    if not file then
      return nil
    end
    local content = file:read("*a")
    file:close()
    
    -- Simple JSON parsing for session_id
    local session_id = content:match('"session_id":"([^"]+)"')
    if session_id then
      return session_id
    end
    
    -- Try alternative JSON format
    session_id = content:match("'session_id':'([^']+)'")
    if session_id then
      return session_id
    end
    
    return nil
  end

  -- Check project-local .vibe/logs/session/
  local project_meta = io.popen('ls -dt "' .. vim.fn.getcwd() .. '/.vibe/logs/session"/session_*/meta.json 2>/dev/null | head -1')
  local project_path = project_meta:read("*l")
  project_meta:close()
  
  if project_path and project_path ~= "" and read_session_id_from_meta(project_path) then
    return read_session_id_from_meta(project_path)
  end

  -- Check global VIBE_HOME or ~/.vibe/logs/session/
  local vibe_home = vim.env.VIBE_HOME or vim.fn.expand("~/.vibe")
  local global_meta = io.popen('ls -dt "' .. vibe_home .. '/logs/session"/session_*/meta.json 2>/dev/null | head -1')
  local global_path = global_meta:read("*l")
  global_meta:close()
  
  if global_path and global_path ~= "" and read_session_id_from_meta(global_path) then
    return read_session_id_from_meta(global_path)
  end

  -- Fallback: try to get from VIBE_SESSION_ID environment variable
  local env_session = vim.env.VIBE_SESSION_ID
  if env_session and env_session ~= "" then
    return env_session
  end

  -- Last resort: return a generic identifier
  return "vibe-" .. vim.fn.getpid()
end

-- Detect terminal type for a buffer
local function detect_terminal_type(buf)
  -- Check buffer variables first (set by claude.lua or vibe.lua)
  if vim.b[buf].terminal_type == 'vibe' then
    return 'vibe'
  end
  if vim.b[buf].terminal_type == 'claude' then
    return 'claude'
  end

  -- Check buffer name for patterns
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if buf_name:match('vibe') or buf_name:match('mistral') then
    return 'vibe'
  end
  if buf_name:match('claude') then
    return 'claude'
  end

  -- Check buffer content for patterns (first few lines)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 5, false)
  for _, line in ipairs(lines) do
    if line:lower():match('vibe') or line:lower():match('mistral') then
      return 'vibe'
    end
    if line:lower():match('claude') then
      return 'claude'
    end
  end

  -- Default to bash
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

  -- Terminal buffer: customize title based on type
  if buftype == 'terminal' then
    local terminal_type = detect_terminal_type(current_buf)

    if terminal_type == 'vibe' then
      -- For Vibe, get the session ID
      local session_id = get_vibe_session_id()
      
      -- If we have a saved session ID in buffer variables, use it
      if vim.b[current_buf].terminal_session_id then
        session_id = vim.b[current_buf].terminal_session_id
      end
      
      return session_id or "vibe"
    elseif terminal_type == 'claude' then
      -- For Claude Code, use claude-<pid>
      if vim.b[current_buf].terminal_pid then
        return "claude-" .. vim.b[current_buf].terminal_pid
      end
      return "claude-" .. vim.fn.getpid()
    else
      -- For bash and other terminals: use current directory
      local cwd
      
      -- Check if we saved the CWD when terminal was opened
      if vim.b[current_buf].terminal_cwd then
        cwd = vim.b[current_buf].terminal_cwd
      else
        -- Try to get CWD from terminal job
        cwd = vim.fn.getcwd()
      end
      
      -- Extract just the directory name
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

  -- Regular buffer: use filename
  if buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":t")
  end

  -- Fallback
  return "[No Name]"
end

-- Update all tab titles
function M.update_all_tab_titles()
  local tab_count = vim.fn.tabpagenr('$')
  for i = 1, tab_count do
    local title = M.get_tab_title(i)
    -- Store title in tab-local variable
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
    
    -- Truncate title if too long
    if #title > 30 then
      title = title:sub(1, 27) .. "..."
    end
    
    -- Determine highlight group
    local highlight
    if i == current_tab then
      highlight = '%#TabLineSel#'
    else
      highlight = '%#TabLine#'
    end
    
    -- Add tab to result
    table.insert(result, string.format('%s %d:%s %s ', highlight, i, title, highlight))
  end

  -- Add fill and X button
  table.insert(result, '%#TabLineFill#%T')
  
  return table.concat(result)
end

-- Setup function
function M.setup()
  -- Enable tabline display
  if vim.o.showtabline < 2 then
    vim.o.showtabline = 2
  end

  -- Define Vim function for tabline (plugin files can't be required directly)
  vim.cmd([[
    function! TabLine()
      return luaeval('_G.tab_titles.tabline()')
    endfunction
  ]])

  -- Set custom tabline
  vim.o.tabline = '%!TabLine()'

  -- Update tab titles on relevant events
  vim.api.nvim_create_autocmd({'TabEnter', 'TabNew', 'BufEnter', 'TermOpen'}, {
    pattern = '*',
    callback = function()
      M.update_all_tab_titles()
    end
  })
end

-- Store module in global variable so it can be accessed from tabline
_G.tab_titles = M

-- Initialize the plugin
M.setup()

return M
