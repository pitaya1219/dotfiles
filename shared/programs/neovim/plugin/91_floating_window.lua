-- Close all floating windows
function CloseAllFloatingWindows()
  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      vim.api.nvim_win_close(win, true)
    end
  end
end

vim.keymap.set("n", "<leader>popca", CloseAllFloatingWindows)
