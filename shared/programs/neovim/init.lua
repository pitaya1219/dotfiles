-- Neovim Lua configuration
-- Load options
dofile(debug.getinfo(1).source:sub(2):gsub('/init%.lua$', '/options.lua'))

-- Load autocommands
dofile(debug.getinfo(1).source:sub(2):gsub('/init%.lua$', '/autocmds.lua'))
-- Load keybindings
dofile(debug.getinfo(1).source:sub(2):gsub('/init%.lua$', '/keybindings.lua'))
-- Load all plugin configurations
local config_dir = debug.getinfo(1).source:sub(2):gsub('/init%.lua$', '')
local plugins_dir = config_dir .. '/plugins'

-- Check if plugins directory exists
if vim.fn.isdirectory(plugins_dir) == 1 then
  -- Get all .lua files in plugins directory
  local plugin_files = vim.fn.glob(plugins_dir .. '/*.lua', false, true)
  for _, file_path in ipairs(plugin_files) do
    dofile(file_path)
  end
end

-- Set default colorscheme
vim.cmd("colorscheme aquarium")
