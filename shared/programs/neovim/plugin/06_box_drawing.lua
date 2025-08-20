-- Box Drawing Plugin
-- Draw box characters with h/l movements

-- State to track if we're in drawing mode
vim.g.box_drawing_mode = false

-- Box drawing character sets
local box_styles = {
  -- Style 1: Heavy box drawing
  {
    horizontal = '━',
    vertical = '┃',
    corners = {
      top_left = '┏',
      top_right = '┓',
      bottom_left = '┗',
      bottom_right = '┛'
    },
    tees = {
      left = '┣',
      right = '┫',
      top = '┳',
      bottom = '┻'
    },
    cross = '╋'
  },
  -- Style 2: Light box drawing
  {
    horizontal = '─',
    vertical = '│',
    corners = {
      top_left = '┌',
      top_right = '┐',
      bottom_left = '└',
      bottom_right = '┘'
    },
    tees = {
      left = '├',
      right = '┤',
      top = '┬',
      bottom = '┴'
    },
    cross = '┼'
  },
  -- Style 3: Double box drawing
  {
    horizontal = '═',
    vertical = '║',
    corners = {
      top_left = '╔',
      top_right = '╗',
      bottom_left = '╚',
      bottom_right = '╝'
    },
    tees = {
      left = '╠',
      right = '╣',
      top = '╦',
      bottom = '╩'
    },
    cross = '╬'
  },
  -- Style 4: ASCII style
  {
    horizontal = '-',
    vertical = '|',
    corners = {
      top_left = '+',
      top_right = '+',
      bottom_left = '+',
      bottom_right = '+'
    },
    tees = {
      left = '+',
      right = '+',
      top = '+',
      bottom = '+'
    },
    cross = '+'
  }
}

-- Current box style (default to style 1)
vim.g.box_drawing_style = 1
local box_chars = box_styles[vim.g.box_drawing_style]

-- Helper functions for position calculations
local function get_cursor_position()
  return {
    col = vim.fn.virtcol('.'),
    line = vim.fn.line('.'),
    last_line = vim.fn.line('$')
  }
end

local function get_line_display_width(line_num)
  local line_content = vim.fn.getline(line_num)
  return vim.fn.strdisplaywidth(line_content)
end

local function create_padding(length)
  return string.rep(' ', math.max(0, length))
end

-- Helper function for vertical movement
local function draw_vertical(char, direction)
  local pos = get_cursor_position()

  if direction == 'j' then
    if pos.line == pos.last_line then
      -- At last line, create new line
      local padding = create_padding(pos.col - 1)
      return 'o<esc>a' .. padding .. char .. '<esc>'
    else
      -- Check next line
      local line_len = get_line_display_width(pos.line + 1)

      if pos.col > line_len then
        -- Need to pad the line below
        local padding = create_padding(pos.col - line_len - 1)
        return 'j$a' .. padding .. char .. '<esc>'
      else
        return 'jr' .. char .. '<esc>'
      end
    end
  else -- direction == 'k'
    if pos.line == 1 then
      -- At first line, create new line above
      local padding = create_padding(pos.col - 1)
      return 'O<esc>a' .. padding .. char .. '<esc>'
    else
      -- Check line above
      local line_len = get_line_display_width(pos.line - 1)

      if pos.col > line_len then
        -- Need to pad the line above
        local padding = create_padding(pos.col - line_len - 1)
        return 'k$a' .. padding .. char .. '<esc>'
      else
        return 'kr' .. char .. '<esc>'
      end
    end
  end
end

-- Function to change box drawing style
local function set_box_style(style_num)
  if style_num >= 1 and style_num <= #box_styles then
    vim.g.box_drawing_style = style_num
    box_chars = box_styles[style_num]
    local style_names = {"Heavy", "Light", "Double", "ASCII"}
    vim.notify("Box style: " .. style_names[style_num], vim.log.levels.INFO)
  end
end

-- Function to enter/exit box drawing mode
local function toggle_box_drawing_mode()
  vim.g.box_drawing_mode = not vim.g.box_drawing_mode
  if vim.g.box_drawing_mode then
    -- Set short timeout for the key sequence
    vim.opt.timeoutlen = 300
    vim.notify("Box drawing mode ON", vim.log.levels.INFO)
    -- Set up statusline indicator
    vim.opt.statusline = "%#WarningMsg#[DRAW MODE]%#StatusLine# " .. vim.o.statusline
  else
    vim.opt.timeoutlen = 1000
    vim.notify("Box drawing mode OFF", vim.log.levels.INFO)
    -- Remove statusline indicator
    local current_statusline = vim.o.statusline
    vim.opt.statusline = current_statusline:gsub("%%#WarningMsg#%[DRAW MODE%]%%#StatusLine# ", "")
  end
end

-- Helper function for horizontal movement
local function draw_horizontal(char, direction)
  local pos = get_cursor_position()

  if direction == 'h' then
    if pos.col == 1 then
      -- At beginning of line, insert
      return 'i' .. char .. '<esc>'
    else
      -- Not at beginning, replace and move left
      return 'r' .. char .. 'h'
    end
  else -- direction == 'l'
    local line_len = vim.fn.virtcol('$') - 1
    if pos.col >= line_len then
      -- At end of line, append
      return 'a' .. char .. '<esc>'
    else
      -- Not at end, replace and move right
      return 'r' .. char .. 'l'
    end
  end
end

-- Function to draw and move
local function draw_and_move(char, direction)
  if not vim.g.box_drawing_mode then
    -- Normal movement when not in drawing mode
    return direction
  end

  if direction == 'h' or direction == 'l' then
    return draw_horizontal(char, direction)
  else -- direction == 'j' or direction == 'k'
    return draw_vertical(char, direction)
  end
end

-- Keymappings
vim.keymap.set('n', '<leader>draw', toggle_box_drawing_mode, { desc = 'Toggle box drawing mode' })

-- Number keys to change box style (only in drawing mode)
for i = 1, 4 do
  vim.keymap.set('n', tostring(i), function()
    if vim.g.box_drawing_mode then
      set_box_style(i)
    else
      -- Normal behavior when not in drawing mode
      return tostring(i)
    end
  end, { expr = true, desc = 'Box style ' .. i })
end

-- Override h/l/j/k in normal mode when box drawing is active
vim.keymap.set('n', '<c-h>', function() return draw_and_move(box_chars.horizontal, 'h') end, { expr = true, desc = 'Draw horizontal left' })
vim.keymap.set('n', '<c-l>', function() return draw_and_move(box_chars.horizontal, 'l') end, { expr = true, desc = 'Draw horizontal right' })
vim.keymap.set('n', '<c-j>', function() return draw_and_move(box_chars.vertical, 'j') end, { expr = true, desc = 'Draw vertical down' })
vim.keymap.set('n', '<c-k>', function() return draw_and_move(box_chars.vertical, 'k') end, { expr = true, desc = 'Draw vertical up' })

-- Function to draw special character only in drawing mode
local function draw_char_and_move(char, direction)
  return function()
    if vim.g.box_drawing_mode then
      -- Replace character at cursor position
      vim.cmd('normal! r' .. char)
      -- Move in the specified direction
      if direction then
        vim.cmd('normal! ' .. direction)
      end
    else
      vim.notify("Box drawing mode is OFF", vim.log.levels.WARN)
    end
  end
end

-- Quick corner drawing (using functions to get current style)
vim.keymap.set('n', '<c-l><c-j>', function() return draw_char_and_move(box_chars.corners.top_right, 'j')() end, { desc = 'Draw top-right corner' })
vim.keymap.set('n', '<c-l><c-k>', function() return draw_char_and_move(box_chars.corners.bottom_right, 'k')() end, { desc = 'Draw bottom-right corner' })
vim.keymap.set('n', '<c-h><c-j>', function() return draw_char_and_move(box_chars.corners.top_left, 'j')() end, { desc = 'Draw top-left corner' })
vim.keymap.set('n', '<c-h><c-k>', function() return draw_char_and_move(box_chars.corners.bottom_left, 'k')() end, { desc = 'Draw bottom-left corner' })
vim.keymap.set('n', '<c-j><c-l>', function() return draw_char_and_move(box_chars.corners.bottom_left, 'l')() end, { desc = 'Draw bottom-left corner' })
vim.keymap.set('n', '<c-j><c-h>', function() return draw_char_and_move(box_chars.corners.bottom_right, 'h')() end, { desc = 'Draw bottom-right corner' })
vim.keymap.set('n', '<c-k><c-l>', function() return draw_char_and_move(box_chars.corners.top_left, 'l')() end, { desc = 'Draw top-left corner' })
vim.keymap.set('n', '<c-k><c-h>', function() return draw_char_and_move(box_chars.corners.top_right, 'h')() end, { desc = 'Draw top-right corner' })
vim.keymap.set('n', '<c-t><c-l>', function() return draw_char_and_move(box_chars.tees.left, 'l')() end, { desc = 'Draw left T' })
vim.keymap.set('n', '<c-t><c-h>', function() return draw_char_and_move(box_chars.tees.right, 'h')() end, { desc = 'Draw right T' })
vim.keymap.set('n', '<c-t><c-j>', function() return draw_char_and_move(box_chars.tees.top, 'j')() end, { desc = 'Draw top T' })
vim.keymap.set('n', '<c-t><c-k>', function() return draw_char_and_move(box_chars.tees.bottom, 'k')() end, { desc = 'Draw bottom T' })
vim.keymap.set('n', '<c-x>', function() return draw_char_and_move(box_chars.cross)() end, { desc = 'Draw cross' })
