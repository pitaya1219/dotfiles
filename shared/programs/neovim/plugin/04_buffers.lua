local msg = {
  no_unactive_buffer = 'There is no unactive buffer.',
}

local function get_buffer_list()
  local buffers_output = vim.fn.execute('ls')
  local lines = vim.split(buffers_output, '\n', { plain = true, trimempty = true })
  local buffer_list = {}

  for _, line in ipairs(lines) do
    local buffer_num = line:match('^%s*(%d+)')
    local name = line:match('"([^"]*)"') or '[No Name]'
    if buffer_num then
      table.insert(buffer_list, { num = buffer_num, name = name, line = line })
    end
  end

  return buffer_list
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

local function create_buffer_list_window(buffer_list)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.4)
  local height = math.min(#buffer_list + 2, 15)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' Buffers ',
    title_pos = 'center',
    zindex = 100
  })
  return buf, win
end

local function manage_buffer()
  local original_buf = vim.api.nvim_get_current_buf()
  local buffer_list = get_buffer_list()
  local filtered_buffer_list = buffer_list
  local search_query = ""

  if #buffer_list == 0 then
    return
  end

  local current_idx = 1
  local preview_buf, preview_win = create_preview_window()
  local buf, win = create_buffer_list_window(buffer_list)

  local function update_preview(selected_buffer)
    if selected_buffer and tonumber(selected_buffer.num) then
      local target_buf = tonumber(selected_buffer.num)
      if vim.api.nvim_buf_is_valid(target_buf) then
        local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
        vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
        local filetype = vim.api.nvim_buf_get_option(target_buf, 'filetype')
        vim.api.nvim_buf_set_option(preview_buf, 'filetype', filetype)
      end
    end
  end

  local function filter_buffers(query)
    if query == "" then
      return buffer_list
    end
    local filtered = {}
    for _, buffer in ipairs(buffer_list) do
      if buffer.name:lower():find(query:lower(), 1, true) then
        table.insert(filtered, buffer)
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
    
    for i, buffer in ipairs(filtered_buffer_list) do
      local prefix = i == current_idx and '> ' or '  '
      local line = string.format('%s%s: %s', prefix, buffer.num, buffer.name)
      table.insert(display_lines, line)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
    if vim.api.nvim_win_is_valid(win) then
      local cursor_row = current_idx + (search_query ~= "" and 2 or 0)
      vim.api.nvim_win_set_cursor(win, {cursor_row, 0})
    end
    if #filtered_buffer_list > 0 then
      update_preview(filtered_buffer_list[current_idx])
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

    -- Restore original buffer if requested, or create new buffer if original was deleted
    if restore_original then
      if original_buf and vim.api.nvim_buf_is_valid(original_buf) then
        vim.cmd('buffer ' .. original_buf)
      else
        -- If original buffer was deleted, open the buffer under cursor if available
        if #buffer_list > 0 then
          local selected_buffer = buffer_list[current_idx]
          vim.cmd('buffer ' .. selected_buffer.num)
        else
          vim.cmd('enew')
        end
      end
    end
  end

  vim.keymap.set('n', 'j', function()
    current_idx = math.min(current_idx + 1, #filtered_buffer_list)
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
    current_idx = #filtered_buffer_list
    update_display()
  end, { buffer = buf })

  vim.keymap.set('n', '<CR>', function()
    if #filtered_buffer_list > 0 then
      local selected_buffer = filtered_buffer_list[current_idx]
      close_window(false)
      vim.cmd('buffer ' .. selected_buffer.num)
    end
  end, { buffer = buf })

  local function delete_buffer()
    if #filtered_buffer_list == 0 then
      return
    end
    
    local selected_buffer = filtered_buffer_list[current_idx]
    local target_buf = tonumber(selected_buffer.num)

    if vim.api.nvim_buf_is_valid(target_buf) then
      local modified = vim.api.nvim_buf_get_option(target_buf, 'modified')
      if modified then
        local choice = vim.fn.input('Save changes or discard? (s/d/N): ')
        if choice:lower() == 's' then
          vim.cmd('buffer ' .. target_buf)
          vim.cmd('write')
          vim.cmd('bdelete')
        elseif choice:lower() == 'd' then
          vim.cmd('bdelete! ' .. target_buf)
        else
          return
        end
      else
        vim.cmd('bdelete ' .. target_buf)
      end

      if target_buf == original_buf then
        original_buf = nil
      end

      -- Remove from original buffer_list
      for i, buffer in ipairs(buffer_list) do
        if buffer.num == selected_buffer.num then
          table.remove(buffer_list, i)
          break
        end
      end
      
      -- Update filtered list
      filtered_buffer_list = filter_buffers(search_query)
      if #filtered_buffer_list == 0 then
        close_window(true)
        return
      end
      if current_idx > #filtered_buffer_list then
        current_idx = #filtered_buffer_list
      end
      update_display()
    end
  end

  local function start_search()
    vim.api.nvim_echo({{'Search: ', 'Normal'}}, false, {})
    local query = vim.fn.input('')
    if query then
      search_query = query
      filtered_buffer_list = filter_buffers(search_query)
      current_idx = 1
      update_display()
    end
  end

  local function clear_search()
    search_query = ""
    filtered_buffer_list = buffer_list
    current_idx = 1
    update_display()
  end

  local function setup_keymaps()
    vim.keymap.set('n', 'j', function()
      current_idx = math.min(current_idx + 1, #filtered_buffer_list)
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
      current_idx = #filtered_buffer_list
      update_display()
    end, { buffer = buf })

    vim.keymap.set('n', '<CR>', function()
      if #filtered_buffer_list > 0 then
        local selected_buffer = filtered_buffer_list[current_idx]
        close_window(false)
        vim.cmd('buffer ' .. selected_buffer.num)
      end
    end, { buffer = buf })

    vim.keymap.set('n', 'd', delete_buffer, { buffer = buf })

    vim.keymap.set('n', 't', function()
      if #filtered_buffer_list > 0 then
        local selected_buffer = filtered_buffer_list[current_idx]
        close_window(false)
        vim.cmd('tabnew')
        vim.cmd('buffer ' .. selected_buffer.num)
      end
    end, { buffer = buf })

    vim.keymap.set('n', '/', start_search, { buffer = buf })
    vim.keymap.set('n', '<C-c>', clear_search, { buffer = buf })

    vim.keymap.set('n', '<Esc>', function() close_window(true) end, { buffer = buf })
    vim.keymap.set('n', 'q', function() close_window(true) end, { buffer = buf })
  end

  setup_keymaps()
  update_display()
end

vim.keymap.set('n', '<leader>bufm', manage_buffer, { silent = true })


vim.keymap.set('n', '<leader>bufc', function()
  -- generate list like following format:
  --   [ [{buffer_num}, {buffer_is_active_or_not}] ]
  -- e.g. [ ['2', 'a'], ['5', ' '] ]
  local buffers_output = vim.fn.execute('ls')
  local lines = vim.split(buffers_output, '\n', { plain = true, trimempty = true })
  local wipeout_nums = {}
  for _, line in ipairs(lines) do
    -- Match buffer number and check for 'a' flag (active buffer)
    -- Buffer list format: "  1 %a   "file.txt"  line 1"
    local buffer_num = line:match('^%s*(%d+)')
    local flags_section = line:match('^%s*%d+%s+([^"]+)')
    if buffer_num and flags_section then
      -- Check if 'a' flag is present (active buffer)
      local is_active = flags_section:find('%%a') ~= nil
      -- Check if it's a terminal buffer
      local is_terminal = line:find('term://') ~= nil
      if not is_active and not is_terminal then
        table.insert(wipeout_nums, buffer_num)
      end
    end
  end
  if #wipeout_nums == 0 then
    vim.api.nvim_echo({{msg.no_unactive_buffer, 'Normal'}}, false, {})
    return
  end
  vim.cmd('bwipeout ' .. table.concat(wipeout_nums, ' '))
end, { silent = true })
