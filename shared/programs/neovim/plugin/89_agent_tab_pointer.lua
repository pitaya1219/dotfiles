-- Shared session-ID pointer protocol for agent terminal tabs.
--
-- Claude Code's SessionStart hook and Vibe's pre_tool/post_agent hooks (see
-- scripts/agent-session-tab-pointer.py) inherit a per-tab AGENT_TAB_MARKER
-- env var and write the authoritative session_id to a pointer file keyed by
-- that marker. 90_claude.lua and 92_vibe.lua both tag their termopen()'d
-- shells with a marker and poll for the resulting file — this module is the
-- one place that protocol (marker format + pointer path + read) lives.

local M = {}

-- Keyed by uid: /tmp is shared across unix accounts on multi-tenant hosts,
-- and whichever account creates the directory first owns it, locking every
-- other account out of writing pointer files (a silent failure, since both
-- the Python hook and the read here swallow errors).
M.POINTER_DIR = string.format("/tmp/agent-tab-sessions-%d", vim.loop.getuid())

local tab_marker_counter = 0

function M.new_marker()
  tab_marker_counter = tab_marker_counter + 1
  return string.format("%d-%d-%d", vim.fn.getpid(), os.time(), tab_marker_counter)
end

function M.read_pointer(marker)
  local f = io.open(M.POINTER_DIR .. "/" .. marker .. ".json", "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  if ok and data and data.session_id and data.session_id ~= "" then
    return data.session_id
  end
  return nil
end

_G.agent_tab_pointer = M

return M
