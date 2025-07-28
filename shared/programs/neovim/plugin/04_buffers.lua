local msg = {
  no_unactive_buffer = 'There is no unactive buffer.',
}


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
