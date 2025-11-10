local msg = {
  no_tabs = 'There are no tabs to manage.',
}

local function get_tab_list()
  local tab_list = {}
  local tab_count = vim.fn.tabpagenr('$')
  
  for i = 1, tab_count do
    local tab_info = {}
    tab_info.num = i
    tab_info.is_current = (i == vim.fn.tabpagenr())
    
    -- Get buffer list for this tab
    local tab_buffers = vim.fn.tabpagebuflist(i)
    local current_buf = tab_buffers[vim.fn.tabpagewinnr(i)]
    local buf_name = vim.api.nvim_buf_get_name(current_buf)
    
    if buf_name == "" then
      tab_info.name = "[No Name]"
    else
      tab_info.name = vim.fn.fnamemodify(buf_name, ":t")
    end
    
    -- Count windows in tab
    tab_info.win_count = #tab_buffers
    
    table.insert(tab_list, tab_info)
  end
  
  return tab_list
end

local function create_preview_window()
  local preview_buf = vim.api.nvim_create_buf(false, true)
  local preview_win = vim.api.nvim_open_win(preview_buf, false, {
    relative = 'editor',
    width = vim.o.columns,
    height = vim.o.lines - 2,
    col = 0,
    row = 0,
    style = 'minimal',
    zindex = 50
  })
  return preview_buf, preview_win
end

local function create_tab_list_window(tab_list)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.4)
  local height = math.min(#tab_list + 2, 15)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' Tabs ',
    title_pos = 'center',
    zindex = 100
  })
  return buf, win
end

local function manage_tabs()
  local original_tab = vim.fn.tabpagenr()
  local tab_list = get_tab_list()
  local filtered_tab_list = tab_list
  local search_query = ""

  if #tab_list <= 1 then
    vim.api.nvim_echo({{msg.no_tabs, 'Normal'}}, false, {})
    return
  end

  local current_idx = 1
  -- Find current tab in list
  for i, tab in ipairs(tab_list) do
    if tab.is_current then
      current_idx = i
      break
    end
  end

  local preview_buf, preview_win = create_preview_window()
  local buf, win = create_tab_list_window(tab_list)

  local function update_preview(selected_tab)
    if selected_tab and vim.api.nvim_buf_is_valid(preview_buf) then
      -- Switch to the tab temporarily to get its content
      local current_tab_before = vim.fn.tabpagenr()
      vim.cmd('tabnext ' .. selected_tab.num)
      
      local current_buf = vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(current_buf) then
        local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
        vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
        local filetype = vim.api.nvim_buf_get_option(current_buf, 'filetype')
        vim.api.nvim_buf_set_option(preview_buf, 'filetype', filetype)
      end
      
      -- Switch back to original tab
      vim.cmd('tabnext ' .. current_tab_before)
    end
  end

  local function filter_tabs(query)
    if query == "" then
      return tab_list
    end
    local filtered = {}
    for _, tab in ipairs(tab_list) do
      if tab.name:lower():find(query:lower(), 1, true) then
        table.insert(filtered, tab)
      end
    end
    return filtered
  end

  local function update_display()
    local display_lines = {}
    
    -- Add search query line if searching
    if search_query ~= "" then
      table.insert(display_lines, "Search: " .. search_query)
      table.insert(display_lines, "")
    end
    
    for i, tab in ipairs(filtered_tab_list) do
      local prefix = i == current_idx and '> ' or '  '
      local current_marker = tab.is_current and '*' or ' '
      local win_info = tab.win_count > 1 and string.format(' (%d wins)', tab.win_count) or ''
      local line = string.format('%s%s%d: %s%s', prefix, current_marker, tab.num, tab.name, win_info)
      table.insert(display_lines, line)
    end
    
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
    end
    if vim.api.nvim_win_is_valid(win) then
      local cursor_row = current_idx + (search_query ~= "" and 2 or 0)
      vim.api.nvim_win_set_cursor(win, {cursor_row, 0})
    end
    if #filtered_tab_list > 0 then
      update_preview(filtered_tab_list[current_idx])
    end
  end

  local function close_window(restore_original)
    if vim.api.nvim_win_is_valid(preview_win) then
      vim.api.nvim_win_close(preview_win, true)
    end
    if vim.api.nvim_buf_is_valid(preview_buf) then
      vim.api.nvim_buf_delete(preview_buf, { force = true })
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    if restore_original then
      vim.cmd('tabnext ' .. original_tab)
    end
  end

  local function delete_tab()
    if #filtered_tab_list == 0 then
      return
    end
    
    local selected_tab = filtered_tab_list[current_idx]
    
    -- Check if any buffers in the tab are modified
    local tab_buffers = vim.fn.tabpagebuflist(selected_tab.num)
    local has_modified = false
    
    for _, buf_num in ipairs(tab_buffers) do
      if vim.api.nvim_buf_is_valid(buf_num) and vim.api.nvim_buf_get_option(buf_num, 'modified') then
        has_modified = true
        break
      end
    end
    
    if has_modified then
      local choice = vim.fn.input('Tab has unsaved changes. Close anyway? (y/N): ')
      if choice:lower() ~= 'y' then
        return
      end
    end

    vim.cmd('tabclose ' .. selected_tab.num)
    
    -- Refresh tab list
    tab_list = get_tab_list()
    filtered_tab_list = filter_tabs(search_query)
    
    if #filtered_tab_list == 0 then
      close_window(true)
      return
    end
    
    if current_idx > #filtered_tab_list then
      current_idx = #filtered_tab_list
    end
    
    update_display()
  end

  local function start_search()
    vim.api.nvim_echo({{'Search: ', 'Normal'}}, false, {})
    local query = vim.fn.input('')
    if query then
      search_query = query
      filtered_tab_list = filter_tabs(search_query)
      current_idx = 1
      update_display()
    end
  end

  local function clear_search()
    search_query = ""
    filtered_tab_list = tab_list
    current_idx = 1
    update_display()
  end

  local function setup_keymaps()
    vim.keymap.set('n', 'j', function()
      current_idx = math.min(current_idx + 1, #filtered_tab_list)
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
      current_idx = #filtered_tab_list
      update_display()
    end, { buffer = buf })

    vim.keymap.set('n', '<CR>', function()
      if #filtered_tab_list > 0 then
        local selected_tab = filtered_tab_list[current_idx]
        close_window(false)
        vim.cmd('tabnext ' .. selected_tab.num)
      end
    end, { buffer = buf })

    vim.keymap.set('n', 'd', delete_tab, { buffer = buf })

    vim.keymap.set('n', 'n', function()
      close_window(false)
      vim.cmd('tabnew')
    end, { buffer = buf })

    vim.keymap.set('n', '/', start_search, { buffer = buf })
    vim.keymap.set('n', '<C-c>', clear_search, { buffer = buf })

    vim.keymap.set('n', '<Esc>', function() close_window(true) end, { buffer = buf })
    vim.keymap.set('n', 'q', function() close_window(true) end, { buffer = buf })
  end

  setup_keymaps()
  update_display()
end

vim.keymap.set('n', '<leader>tabm', manage_tabs, { silent = true })

-- Move to tab with running terminal
vim.keymap.set('n', '<leader>tabt', function()
  -- Find terminal buffer and its tab
  local tab_count = vim.fn.tabpagenr('$')
  local terminal_tab = nil

  for i = 1, tab_count do
    local tab_buffers = vim.fn.tabpagebuflist(i)
    for _, buf in ipairs(tab_buffers) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_option(buf, 'buftype') == 'terminal' then
        terminal_tab = i
        break
      end
    end
    if terminal_tab then
      break
    end
  end

  if terminal_tab then
    vim.cmd('tabn ' .. terminal_tab)
  else
    vim.api.nvim_echo({{'No running terminal found.', 'WarningMsg'}}, false, {})
  end
end, { silent = true, desc = 'Move to tab with running terminal' })
