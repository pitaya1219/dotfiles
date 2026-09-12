-- Projects the comment drafts a /my-review run leaves behind onto the lines
-- they are about, and takes the reviewer's edits and feedback back.
--
-- The review file is the whole contract with the agent session:
--
--   <git-common-dir>/my-review/review.json
--
-- Its schema is documented once, in the skill that writes it
-- (shared/programs/agent/skills/my-review/SKILL.md, Phase 3.5). Of a comment's
-- fields only `body`, `status`, `feedback` and `edited_at` are ever written
-- from here; the rest is the agent's, and is read back off disk and written
-- out untouched so a rewrite from this side cannot drop what it did not know
-- about. Applying the feedback is the agent's job too -- this side only
-- records it.
--
-- Every profile gets this file, and it stays inert until a review file turns
-- up next to a buffer, which is why it does not sit behind the same profile
-- opt-in as the skill (dotfiles.agent.skills in shared/programs/agent.nix).
--
-- The presentation follows llama.vim's instruction feature (see
-- profiles/r-shibuya/neovim/plugin/10_llama.lua): the source lines carry a
-- background tint and the generated text hangs underneath them in virtual
-- lines, ruled off top and bottom.

local ns = vim.api.nvim_create_namespace("my_review")

local REVIEW_FILE = "my-review/review.json"

-- llama.vim's own palette, so the two features read as one thing on screen:
-- orange for what wants a decision, green for what does not.
local highlights = {
  MyReviewMustFix = { fg = "#ff772f", ctermfg = 202 },
  MyReviewOptional = { fg = "#77ff2f", ctermfg = 119 },
  MyReviewFeedback = { fg = "#2fb6ff", ctermfg = 75 },
  MyReviewSrc = { bg = "#554433", ctermbg = 236 },
  MyReviewBody = { link = "Normal" },
  MyReviewCode = { link = "DiffAdd" },
  MyReviewDropped = { link = "Comment" },
}

for name, spec in pairs(highlights) do
  vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, spec))
end

-- The labels are the notation the review itself is written in, so what is on
-- screen is what ends up on the PR.
local severities = {
  ["must-fix"] = { label = "must-fix", hl = "MyReviewMustFix" },
  ["suggestion"] = { label = "[suggestion]", hl = "MyReviewOptional" },
  ["want"] = { label = "[want]", hl = "MyReviewOptional" },
  ["任意"] = { label = "[任意]", hl = "MyReviewOptional" },
}

local state = {
  file = nil, -- the loaded review.json
  root = nil, -- worktree its `file` fields are relative to
  mtime = nil,
  entries = {}, -- { comment, index } in document order
  by_file = {}, -- relative path -> the entries in that file
  total = 0,
  mode = "full", -- full | compact | off
}

--- JSON ----------------------------------------------------------------------

-- vim.json.encode writes one line, which would make the file unreadable for
-- the half of its life it spends being inspected by hand or by an agent
-- reading it back. Scalars still go through it so the escaping is nvim's.
local key_order = {
  "version", "repo", "pr", "base", "head", "generated_at", "decision", "summary", "comments",
  "id", "file", "line", "end_line", "severity", "status", "body", "suggestion", "feedback", "edited_at",
}

local key_rank = {}
for rank, key in ipairs(key_order) do
  key_rank[key] = rank
end

local function sorted_keys(tbl)
  local keys = vim.tbl_keys(tbl)
  table.sort(keys, function(a, b)
    local rank_a, rank_b = key_rank[a] or math.huge, key_rank[b] or math.huge
    if rank_a ~= rank_b then
      return rank_a < rank_b
    end
    return a < b
  end)
  return keys
end

local function encode(value, indent)
  indent = indent or ""
  if type(value) ~= "table" then
    return vim.json.encode(value)
  end

  local inner = indent .. "  "
  local parts = {}

  -- An empty table is written as an array: every collection in the schema is
  -- one, and an object that lost all its fields has nothing to round-trip.
  if next(value) == nil or vim.islist(value) then
    if next(value) == nil then
      return "[]"
    end
    for _, item in ipairs(value) do
      parts[#parts + 1] = inner .. encode(item, inner)
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
  end

  for _, key in ipairs(sorted_keys(value)) do
    parts[#parts + 1] = inner .. vim.json.encode(key) .. ": " .. encode(value[key], inner)
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function read_document(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()

  local ok, document = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if not ok or type(document) ~= "table" or type(document.comments) ~= "table" then
    vim.notify("my-review: " .. path .. " is not a review file", vim.log.levels.ERROR)
    return nil
  end
  return document
end

local function write_document(path, document)
  local temporary = path .. ".tmp"
  local file = io.open(temporary, "w")
  if not file then
    vim.notify("my-review: cannot write " .. path, vim.log.levels.ERROR)
    return false
  end
  file:write(encode(document) .. "\n")
  file:close()
  return vim.uv.fs_rename(temporary, path) and true or false
end

--- Locating the review file --------------------------------------------------

local git_cache = {}

local function git_info(dir)
  if git_cache[dir] ~= nil then
    return git_cache[dir] or nil
  end

  local out = vim.system(
    { "git", "-C", dir, "rev-parse", "--show-toplevel", "--git-common-dir" },
    { text = true }
  ):wait()

  local info = false
  if out.code == 0 then
    local lines = vim.split(vim.trim(out.stdout or ""), "\n")
    local root, git_dir = lines[1], lines[2]
    if root and git_dir then
      -- --git-common-dir answers relative to git's own -C directory.
      if not vim.startswith(git_dir, "/") then
        git_dir = vim.fs.joinpath(dir, git_dir)
      end
      info = {
        root = vim.fs.normalize(root),
        review = vim.fs.normalize(vim.fs.joinpath(git_dir, REVIEW_FILE)),
      }
    end
  end

  git_cache[dir] = info
  return info or nil
end

local function info_for_buffer(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" then
    return nil
  end
  return git_info(vim.fs.dirname(name))
end

local function current_info()
  return info_for_buffer(vim.api.nvim_get_current_buf()) or git_info(vim.uv.cwd())
end

--- Rendering -----------------------------------------------------------------

local function style_of(comment)
  local style = severities[comment.severity]
      or { label = comment.severity or "?", hl = "MyReviewOptional" }
  if comment.status == "dropped" then
    return { label = style.label, hl = "MyReviewDropped" }
  end
  return style
end

-- Breaks on a space where there is one so western words stay whole; Japanese
-- has none, and there the break falls wherever the width runs out.
local function wrap(text, width)
  local lines = {}
  for _, paragraph in ipairs(vim.split(text or "", "\n", { plain = true })) do
    local current = {}
    for _, char in ipairs(vim.fn.split(paragraph, "\\zs")) do
      if #current > 0 and vim.fn.strdisplaywidth(table.concat(current) .. char) > width then
        local cut = #current
        for i = #current, math.max(1, #current - 16), -1 do
          if current[i] == " " then
            cut = i - 1
            break
          end
        end
        lines[#lines + 1] = table.concat(vim.list_slice(current, 1, cut))
        current = vim.list_slice(current, cut + 2, #current)
      end
      current[#current + 1] = char
    end
    lines[#lines + 1] = table.concat(current)
  end
  return lines
end

local function header_of(entry)
  local comment = entry.comment
  local range = tostring(comment.line or 1)
  if comment.end_line and comment.end_line ~= comment.line then
    range = range .. "-" .. comment.end_line
  end
  return string.format(
    "[%d/%d] %s  %s:%s",
    entry.index, state.total, style_of(comment).label, comment.file, range
  )
end

local function virt_lines_of(entry, width)
  local comment = entry.comment
  local style = style_of(comment)
  local header = header_of(entry)
  local dropped = comment.status == "dropped"
  local rows = {}

  local function add(text, hl)
    rows[#rows + 1] = { text, dropped and "MyReviewDropped" or hl }
  end

  for _, line in ipairs(wrap(comment.body or "", width)) do
    add("  " .. line, "MyReviewBody")
  end

  if comment.suggestion and comment.suggestion ~= "" then
    add("  suggestion", style.hl)
    for _, line in ipairs(vim.split(comment.suggestion, "\n", { plain = true })) do
      add("  │ " .. line, "MyReviewCode")
    end
  end

  if comment.feedback and comment.feedback ~= "" then
    for i, line in ipairs(wrap(comment.feedback, width - 6)) do
      -- Written past `add` so the reviewer's own words keep their colour on a
      -- dropped comment too: that is where the reason for dropping it is.
      rows[#rows + 1] = { (i == 1 and "  FB> " or "      ") .. line, "MyReviewFeedback" }
    end
  end

  if dropped then
    add("  dropped -- will not be posted", "MyReviewDropped")
  end

  local rule = vim.fn.strdisplaywidth(header) + 6
  for _, row in ipairs(rows) do
    rule = math.max(rule, vim.fn.strdisplaywidth(row[1]))
  end

  local top = "── " .. header .. " " .. string.rep("─", rule - vim.fn.strdisplaywidth(header) - 4)
  local virt_lines = { { { top, style.hl } } }
  for _, row in ipairs(rows) do
    virt_lines[#virt_lines + 1] = { { row[1], row[2] } }
  end
  virt_lines[#virt_lines + 1] = { { string.rep("─", rule), style.hl } }
  return virt_lines
end

local function entries_for_buffer(buf)
  if not state.root then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  local relative = vim.fs.relpath(state.root, vim.fs.normalize(name))
  return relative and state.by_file[relative] or nil
end

local function render_buffer(buf)
  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local entries = entries_for_buffer(buf)
  if not entries or state.mode == "off" then
    return
  end

  local last = vim.api.nvim_buf_line_count(buf)
  local width = math.min(math.max(vim.o.columns - 8, 40), 100)

  for _, entry in ipairs(entries) do
    local comment = entry.comment
    local style = style_of(comment)
    local start_row = math.min(math.max(comment.line or 1, 1), last) - 1
    local end_row = math.min(math.max(comment.end_line or comment.line or 1, comment.line or 1), last) - 1
    local end_line = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ""

    local tag = "  " .. style.label
    if (comment.line or 1) > last then
      tag = tag .. " (line " .. comment.line .. " is past the end of this file)"
    end

    vim.api.nvim_buf_set_extmark(buf, ns, start_row, 0, {
      end_row = end_row,
      end_col = #end_line,
      hl_group = comment.status == "dropped" and "MyReviewDropped" or "MyReviewSrc",
      virt_text = { { tag, style.hl } },
      virt_text_pos = "eol",
    })

    if state.mode == "full" then
      vim.api.nvim_buf_set_extmark(buf, ns, end_row, 0, {
        virt_lines = virt_lines_of(entry, width),
      })
    end
  end
end

local function render_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    render_buffer(vim.api.nvim_win_get_buf(win))
  end
end

--- Loading -------------------------------------------------------------------

local function index_document(document)
  state.entries, state.by_file, state.total = {}, {}, #document.comments
  for index, comment in ipairs(document.comments) do
    local entry = { comment = comment, index = index }
    state.entries[#state.entries + 1] = entry
    local file = comment.file or ""
    state.by_file[file] = state.by_file[file] or {}
    table.insert(state.by_file[file], entry)
  end
end

local announced = {}

local function load(path, root, silent)
  local document = read_document(path)
  if not document then
    return false
  end

  local stat = vim.uv.fs_stat(path)
  state.file, state.root, state.mtime = path, root, stat and stat.mtime.nsec + stat.mtime.sec * 1e9 or nil
  index_document(document)
  render_all()

  -- Moving between two repositories in one nvim reloads each review as its
  -- buffers come back up, and announcing a review that has not changed since
  -- it was last announced is just noise.
  if not silent and announced[path] ~= state.mtime then
    announced[path] = state.mtime
    local dropped, feedback = 0, 0
    for _, entry in ipairs(state.entries) do
      if entry.comment.status == "dropped" then
        dropped = dropped + 1
      end
      if entry.comment.feedback and entry.comment.feedback ~= "" then
        feedback = feedback + 1
      end
    end
    vim.notify(string.format(
      "my-review: %d comments loaded (%d dropped, %d with feedback)",
      state.total, dropped, feedback
    ))
  end
  return true
end

-- Called often and cheaply: the review file appears while nvim is already
-- sitting on the code, so every look back at a buffer restats it.
local function refresh(buf)
  local info = info_for_buffer(buf)
  if not info then
    return
  end

  local stat = vim.uv.fs_stat(info.review)
  if not stat then
    if state.file == info.review then
      state.file, state.mtime, state.entries, state.by_file, state.total = nil, nil, {}, {}, 0
      render_all()
    end
    return
  end

  local mtime = stat.mtime.nsec + stat.mtime.sec * 1e9
  if state.file == info.review and state.mtime == mtime then
    render_buffer(buf)
    return
  end
  load(info.review, info.root, false)
end

--- Editing -------------------------------------------------------------------

-- Re-reads the file before touching it: the agent session owns everything but
-- the four fields written from here, and may have rewritten the review since
-- it was loaded.
local function update_comment(id, mutate)
  if not state.file then
    return
  end

  local document = read_document(state.file)
  if not document then
    return
  end

  local found = false
  for _, comment in ipairs(document.comments) do
    if comment.id == id then
      mutate(comment)
      found = true
      break
    end
  end

  if not found then
    vim.notify("my-review: comment " .. tostring(id) .. " is gone from the review file", vim.log.levels.WARN)
    load(state.file, state.root, true)
    return
  end

  if write_document(state.file, document) then
    load(state.file, state.root, true)
  end
end

local function entry_at_cursor(callback)
  local buf = vim.api.nvim_get_current_buf()
  local entries = entries_for_buffer(buf)
  if not entries then
    vim.notify("my-review: no comments in this file", vim.log.levels.WARN)
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local hits = {}
  for _, entry in ipairs(entries) do
    local first = entry.comment.line or 1
    local last = entry.comment.end_line or first
    if row >= first and row <= last then
      hits[#hits + 1] = entry
    end
  end

  if #hits == 0 then
    vim.notify("my-review: no comment on this line", vim.log.levels.WARN)
  elseif #hits == 1 then
    callback(hits[1])
  else
    vim.ui.select(hits, { prompt = "my-review", format_item = header_of }, function(choice)
      if choice then
        callback(choice)
      end
    end)
  end
end

local function open_editor(name, title, footer, text, on_write)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "my-review://" .. name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text or "", "\n", { plain = true }))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modified = false

  local lines = vim.api.nvim_buf_line_count(buf)
  local width = math.min(math.max(vim.o.columns - 8, 40), 84)
  local height = math.min(math.max(lines + 2, 6), math.max(vim.o.lines - 6, 6))

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
    footer = " " .. footer .. " ",
    footer_pos = "center",
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local written = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      vim.bo[buf].modified = false
      vim.api.nvim_buf_delete(buf, { force = true })
      on_write(written)
    end,
  })

  vim.keymap.set("n", "q", "<Cmd>bwipeout!<CR>", { buffer = buf, nowait = true })
end

local function edit_body()
  entry_at_cursor(function(entry)
    local comment = entry.comment
    open_editor(comment.id .. "/body", header_of(entry), ":w save   q discard", comment.body, function(text)
      update_comment(comment.id, function(target)
        if target.body ~= text then
          target.body = text
          target.edited_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
        end
      end)
    end)
  end)
end

local function edit_feedback()
  entry_at_cursor(function(entry)
    local comment = entry.comment
    local title = "feedback for " .. header_of(entry)
    open_editor(comment.id .. "/feedback", title, ":w save   q discard", comment.feedback, function(text)
      update_comment(comment.id, function(target)
        target.feedback = vim.trim(text) ~= "" and text or nil
      end)
    end)
  end)
end

local function toggle_dropped()
  entry_at_cursor(function(entry)
    update_comment(entry.comment.id, function(target)
      target.status = target.status == "dropped" and "open" or "dropped"
    end)
  end)
end

--- Navigation ----------------------------------------------------------------

local function jump(direction)
  if #state.entries == 0 then
    vim.notify("my-review: no review loaded", vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local here = state.root and name ~= "" and vim.fs.relpath(state.root, vim.fs.normalize(name)) or nil
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Document order is the order the review reads in, so following it across
  -- files walks the review rather than the repository.
  local ordered = direction > 0 and state.entries or vim.iter(state.entries):rev():totable()
  local current = nil
  for position, entry in ipairs(ordered) do
    if entry.comment.file == here and entry.comment.line == row then
      current = position
    end
  end

  local function is_ahead(entry)
    if entry.comment.file ~= here then
      return true
    end
    return direction > 0 and entry.comment.line > row or entry.comment.line < row
  end

  local target = nil
  for position, entry in ipairs(ordered) do
    if (current and position > current) or (not current and is_ahead(entry)) then
      target = entry
      break
    end
  end
  target = target or ordered[1]

  local path = vim.fs.joinpath(state.root, target.comment.file)
  if vim.fs.normalize(path) ~= vim.fs.normalize(name) then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  local last = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.min(target.comment.line or 1, last), 0 })
  vim.cmd("normal! zz")
end

local function to_quickfix()
  if #state.entries == 0 then
    vim.notify("my-review: no review loaded", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, entry in ipairs(state.entries) do
    local comment = entry.comment
    local first = vim.split(comment.body or "", "\n", { plain = true })[1] or ""
    items[#items + 1] = {
      filename = vim.fs.joinpath(state.root, comment.file),
      lnum = comment.line or 1,
      text = string.format("%s %s", style_of(comment).label, first),
    }
  end

  vim.fn.setqflist({}, " ", { title = "my-review", items = items })
  vim.cmd.copen()
end

--- Commands and keymaps ------------------------------------------------------

local function load_from_argument(path)
  if path and path ~= "" then
    path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    local info = git_info(vim.fs.dirname(path))
    load(path, info and info.root or vim.uv.cwd(), false)
    return
  end

  local info = current_info()
  if not info then
    vim.notify("my-review: not in a git worktree", vim.log.levels.WARN)
    return
  end
  if not vim.uv.fs_stat(info.review) then
    vim.notify("my-review: no review at " .. info.review, vim.log.levels.WARN)
    return
  end
  load(info.review, info.root, false)
end

local function cycle_mode()
  local next_mode = { full = "compact", compact = "off", off = "full" }
  state.mode = next_mode[state.mode]
  render_all()
  vim.notify("my-review: " .. state.mode)
end

local keymaps = {
  { "<leader>rvl", "load or reload the review file", load_from_argument },
  { "<leader>rvt", "cycle the overlay: full, compact, off", cycle_mode },
  { "<leader>rvq", "send every comment to the quickfix list", to_quickfix },
  { "<leader>rve", "edit the comment on this line", edit_body },
  { "<leader>rvf", "leave feedback on the comment for the agent", edit_feedback },
  { "<leader>rvd", "drop the comment on this line, or take it back", toggle_dropped },
  { "]r", "next comment", function() jump(1) end },
  { "[r", "previous comment", function() jump(-1) end },
}

for _, keymap in ipairs(keymaps) do
  vim.keymap.set("n", keymap[1], keymap[3], { desc = "my-review: " .. keymap[2] })
end

-- Listed the same way llama.vim's keymaps are (<leader>ll?), off the table the
-- mappings are made from, so it cannot describe a key that is not in force.
local function show_keymaps()
  local lines, marks, width = {}, {}, 0

  local function add(text)
    lines[#lines + 1] = text
    width = math.max(width, vim.fn.strdisplaywidth(text))
    return #lines - 1
  end

  local function mark(row, col, len, hl)
    marks[#marks + 1] = { row, col, len, hl }
  end

  if state.file then
    mark(add(string.format("%d comments, overlay %s", state.total, state.mode)), 0, -1, "Comment")
    mark(add(state.file), 0, -1, "Comment")
  else
    mark(add("no review loaded"), 0, -1, "Comment")
  end

  add("")
  for _, keymap in ipairs(keymaps) do
    mark(add(string.format("  %-14s %s", keymap[1], keymap[2])), 2, #keymap[1], "Special")
  end
  add("")
  mark(add("  the agent applies the feedback; this side only records it"), 0, -1, "Comment")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local namespace = vim.api.nvim_create_namespace("my_review_keymaps")
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
    title = " my-review ",
    title_pos = "center",
  })

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<Cmd>close<CR>", { buffer = buf, nowait = true })
  end
end

vim.keymap.set("n", "<leader>rv?", show_keymaps, { desc = "my-review: list the <leader>rv keymaps" })

vim.api.nvim_create_user_command("ReviewLoad", function(opts)
  load_from_argument(opts.args)
end, { nargs = "?", complete = "file", desc = "my-review: load a review file" })

vim.api.nvim_create_user_command("ReviewList", to_quickfix,
  { desc = "my-review: send every comment to the quickfix list" })

vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
  callback = function(args)
    refresh(args.buf)
  end,
})

vim.api.nvim_create_autocmd("VimResized", { callback = render_all })
