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
