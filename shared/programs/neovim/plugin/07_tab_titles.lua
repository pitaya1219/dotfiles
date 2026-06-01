-- Dynamic tab title management for Neovim
-- Sets tab titles based on terminal type:
-- - bash terminal: current directory name
-- - claude code terminal: first 8 chars of Claude session UUID
-- - vibe terminal: first 8 chars of Vibe session UUID

local M = {}

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

  -- Prefer claude/vibe terminal over the focused window
  local agent_buf
  for _, buf in ipairs(tab_buffers) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' then
      local t = detect_terminal_type(buf)
      if t == 'claude' or t == 'vibe' then
        agent_buf = buf
        break
      end
    end
  end

  local current_buf = agent_buf or tab_buffers[vim.fn.tabpagewinnr(tabnr)]

  if not vim.api.nvim_buf_is_valid(current_buf) then
    return ""
  end

  local buftype = vim.bo[current_buf].buftype
  local buf_name = vim.api.nvim_buf_get_name(current_buf)

  if buftype == 'terminal' then
    local terminal_type = detect_terminal_type(current_buf)

    if terminal_type == 'vibe' then
      local session_id = vim.b[current_buf].terminal_session_id
      if session_id then
        return "vibe-" .. tostring(session_id):sub(1, 8)
      end
      return "vibe"
    elseif terminal_type == 'claude' then
      local session_id = vim.b[current_buf].terminal_session_id
      if session_id then
        return "claude-" .. tostring(session_id):sub(1, 8)
      end
      return "claude"
    else
      local pid = vim.b[current_buf].terminal_job_pid
      local cwd
      if vim.b[current_buf].terminal_cwd then
        cwd = vim.b[current_buf].terminal_cwd
      else
        cwd = vim.fn.getcwd()
      end
      local dir_name = cwd and (cwd:match('([^/]+)$') or cwd) or "terminal"
      if pid then
        return pid .. ":" .. dir_name
      end
      return dir_name
    end
  end

  if buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":t")
  end

  return "[No Name]"
end

-- Update all tab titles
function M.update_all_tab_titles()
  vim.cmd('redrawtabline')
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

    -- %{i}T marks the clickable region for tab i (enables mouse/touch tap)
    table.insert(result, string.format('%%%dT%s %d:%s %%T ', i, highlight, i, title))
  end

  table.insert(result, '%#TabLineFill#%T')

  return table.concat(result)
end

-- Setup function
function M.setup()
  if vim.o.showtabline < 2 then
    vim.o.showtabline = 2
  end

  -- Enable mouse in all modes so touch/click on tabline works
  if not vim.o.mouse:find('a') then
    vim.o.mouse = 'a'
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
