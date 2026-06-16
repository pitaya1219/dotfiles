local ok, notify = pcall(require, "notify")
if not ok then return end

local stages_util = require("notify.stages.util")

-- 右下から出現し、右上へ上昇、そこでフェードアウトするカスタムステージ
local rise_from_bottom = function(direction)
  return {
    function(state)
      local next_height = state.message.height + 2
      if not stages_util.available_slot(state.open_windows, next_height, direction) then
        return nil
      end
      local bottom, _ = stages_util.get_slot_range(stages_util.DIRECTION.BOTTOM_UP)
      return {
        relative = "editor",
        anchor = "NE",
        width = state.message.width,
        height = state.message.height,
        col = vim.opt.columns:get(),
        row = bottom - state.message.height,
        border = "rounded",
        style = "minimal",
        opacity = 0,
      }
    end,
    function(state, win)
      return {
        opacity = { 100 },
        col = { vim.opt.columns:get() },
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = 0.01,
          damping = 1,
        },
      }
    end,
    function(state, win)
      return {
        col = { vim.opt.columns:get() },
        time = true,
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = 3,
          complete = function() return true end,
        },
      }
    end,
    function(state, win)
      return {
        opacity = {
          0,
          frequency = 2,
          complete = function(cur_opacity) return cur_opacity <= 4 end,
        },
        col = { vim.opt.columns:get() },
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = 3,
          complete = function() return true end,
        },
      }
    end,
  }
end

notify.setup({
  stages = rise_from_bottom(stages_util.DIRECTION.TOP_DOWN),
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

vim.keymap.set("n", "<leader>notic", function()
  notify.dismiss({ silent = true, pending = true })
end, { desc = "Dismiss all notifications" })
vim.keymap.set("n", "<leader>notih", notify.history, { desc = "Notification history" })
