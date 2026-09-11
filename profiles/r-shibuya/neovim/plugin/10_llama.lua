-- llama.vim merges g:llama_config over its own defaults as plugin/llama.vim
-- loads, so this file has to be under plugin/ rather than after/plugin/ to be
-- read at all -- enable_at_startup and the keymaps are only looked at there.
--
-- It drives two local llama-servers, one at a time (profiles/r-shibuya/llama.nix):
--
--   gemma-4-e2b        on 11434  the instruction feature, and the login default
--   Qwen2.5-Coder-3B   on  8012  FIM ghost-text completion
vim.g.llama_config = {
  -- <c-i> and <Tab> are the same keycode in a terminal, so accept_word keeps
  -- the key that used to accept a copilot word. These maps are buffer-local
  -- and live only while a suggestion is on screen, which leaves the <TAB> coc
  -- completion in shared/programs/neovim/plugin/10_coc.lua alone the rest of
  -- the time. accept_full moves off its own <Tab> default so the two do not
  -- collide.
  keymap_fim_accept_word = "<Tab>",
  keymap_fim_accept_line = "<S-Tab>",
  keymap_fim_accept_full = "<C-Y>",

  -- Asking for a completion by hand is an insert-mode action, and the default
  -- <leader>llf is bound with inoremap.
  keymap_fim_trigger = "<C-F>",

  -- The instruction feature wants a chat model, which is the one on 11434.
  endpoint_inst = "http://127.0.0.1:11434/v1/chat/completions",
  model_inst = "gemma-4-e2b",

  -- Gemma 4 reasons unless the request says otherwise. params_inst is the
  -- patch in ../plugins.nix.
  params_inst = { reasoning_effort = "none" },

  -- These two default to <Tab> and <Esc>, mapped globally in normal mode for
  -- as long as the plugin is enabled, which costs the jumplist its <C-I> and
  -- makes <Esc> run a command.
  keymap_inst_accept = "<leader>lla",
  keymap_inst_cancel = "<leader>llx",

  -- Ghost text waits until <leader>llf has loaded the completion model, so
  -- auto_fim does not fire a request at a port nothing is listening on after
  -- every keystroke.
  auto_fim = false,
}

-- Assigning a table back to vim.g would turn the empty stop_strings lists into
-- dictionaries, so the one field that changes at runtime is edited in place.
-- setup_autocmds is what reads auto_fim, so it has to run again to take.
local function set_auto_fim(on)
  vim.cmd("let g:llama_config.auto_fim = " .. (on and "v:true" or "v:false"))
  vim.fn["llama#setup_autocmds"]()
end

-- llama-use returns once the server it loaded answers /health, so turning
-- ghost text on waits for that and turning it off does not.
local function use(target, auto_fim)
  if not auto_fim then
    set_auto_fim(false)
  end

  vim.system({ "llama-use", target }, {}, vim.schedule_wrap(function(out)
    if out.code ~= 0 then
      vim.notify("llama-use " .. target .. ": " .. (out.stderr or "failed"), vim.log.levels.WARN)
      return
    end
    if auto_fim then
      set_auto_fim(true)
    end
  end))
end

vim.keymap.set("n", "<leader>llf", function() use("fim", true) end,
  { desc = "llama: load the completion model and turn ghost text on" })

vim.keymap.set("n", "<leader>llg", function() use("chat", false) end,
  { desc = "llama: load gemma for the instruction feature and turn ghost text off" })

-- The keys are read back out of g:llama_config rather than listed a second
-- time here, so this cannot describe a mapping that is not the one in force.
local function show_keymaps()
  local cfg = vim.g.llama_config or {}
  local groups = {
    { "switch", {
      { "<leader>llf", "load the completion model, ghost text on" },
      { "<leader>llg", "load gemma, ghost text off" },
      { "<leader>ll?", "this list" },
    } },
    { "instruction, needs gemma", {
      { cfg.keymap_inst_trigger, "apply an instruction to the selection" },
      { cfg.keymap_inst_rerun, "run the last instruction again" },
      { cfg.keymap_inst_continue, "follow the last instruction with another" },
      { cfg.keymap_inst_accept, "keep the result" },
      { cfg.keymap_inst_cancel, "discard the result" },
    } },
    { "completion, while a suggestion is on screen", {
      { cfg.keymap_fim_trigger, "ask for one by hand, in insert mode" },
      { cfg.keymap_fim_accept_word, "accept a word" },
      { cfg.keymap_fim_accept_line, "accept a line" },
      { cfg.keymap_fim_accept_full, "accept all of it" },
      { cfg.keymap_fim_next, "next suggestion" },
      { cfg.keymap_fim_prev, "previous suggestion" },
    } },
    { "other", {
      { cfg.keymap_debug_toggle, "debug pane" },
      { ":LlamaStatus", "which server is answering" },
    } },
  }

  local lines, marks, width = {}, {}, 0
  local function add(text)
    lines[#lines + 1] = text
    width = math.max(width, vim.fn.strdisplaywidth(text))
    return #lines - 1
  end
  local function mark(row, col, len, hl)
    marks[#marks + 1] = { row, col, len, hl }
  end

  mark(add(cfg.auto_fim and "ghost text is on" or "ghost text is off"), 0, -1, "Comment")

  for _, group in ipairs(groups) do
    local rows = vim.tbl_filter(function(entry)
      return entry[1] and entry[1] ~= ""
    end, group[2])

    if #rows > 0 then
      add("")
      mark(add(group[1]), 0, -1, "Title")
      for _, entry in ipairs(rows) do
        mark(add(string.format("  %-14s %s", entry[1], entry[2])), 2, #entry[1], "Special")
      end
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local namespace = vim.api.nvim_create_namespace("llama_keymaps")
  for _, m in ipairs(marks) do
    local row, col, len, hl = m[1], m[2], m[3], m[4]
    vim.api.nvim_buf_set_extmark(buf, namespace, row, col, {
      end_col = len < 0 and #lines[row + 1] or col + len,
      hl_group = hl,
    })
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local height = math.min(#lines, vim.o.lines - 4)
  width = math.min(width + 2, vim.o.columns - 4)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " llama ",
    title_pos = "center",
  })

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<Cmd>close<CR>", { buffer = buf, nowait = true })
  end
end

vim.keymap.set("n", "<leader>ll?", show_keymaps,
  { desc = "llama: list the <leader>ll keymaps" })
