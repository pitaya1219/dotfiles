local ok, specs = pcall(require, "specs")
if not ok then return end

specs.setup({
  show_jumps = true,
  min_jump = 30,
  popup = {
    delay_ms = 0,
    inc_ms = 10,
    blend = 10,
    width = 10,
    winhl = "PMenu",
    fader = specs.linear_fader,
    resizer = specs.shrink_resizer,
  },
  ignore_filetypes = {},
  ignore_buftypes = {
    nofile = true,
  },
})
