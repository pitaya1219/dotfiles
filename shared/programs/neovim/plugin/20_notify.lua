local ok, notify = pcall(require, "notify")
if not ok then return end

notify.setup({
  stages = "fade_in_slide_out",
  render = "default",
  timeout = 4000,
  minimum_width = 40,
  max_width = 60,
  max_height = 10,
  top_down = true,
  fps = 30,
  level = vim.log.levels.INFO,
})

vim.notify = notify

-- Keymaps
vim.keymap.set("n", "<leader>notic", function()
  notify.dismiss({ silent = true, pending = true })
end, { desc = "Dismiss all notifications" })
vim.keymap.set("n", "<leader>notih", notify.history, { desc = "Notification history" })
