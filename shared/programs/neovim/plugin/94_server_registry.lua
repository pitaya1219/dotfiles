-- Register this nvim instance in a shared server list so that external scripts
-- (e.g. scripts/nvim-notify.sh) can discover and send notifications via RPC.
--
-- Registry file: stdpath('data')/servers  (~/.local/share/nvim/servers)
-- Each line is an absolute path to a nvim server socket (vim.v.servername).
-- On VimEnter: stale sockets are pruned and the current server is appended.
-- On VimLeave: the current server is removed.

local registry = vim.fn.stdpath('data') .. '/servers'

local function register()
  local addr = vim.v.servername
  if addr == '' then return end

  local lines = {}
  local f = io.open(registry, 'r')
  if f then
    for line in f:lines() do
      if line ~= '' and line ~= addr then
        local stat = vim.uv.fs_stat(line)
        if stat and stat.type == 'socket' then
          table.insert(lines, line)
        end
      end
    end
    f:close()
  end

  table.insert(lines, addr)

  f = io.open(registry, 'w')
  if not f then return end
  for _, line in ipairs(lines) do
    f:write(line .. '\n')
  end
  f:close()
end

local function unregister()
  local addr = vim.v.servername
  if addr == '' then return end

  local f = io.open(registry, 'r')
  if not f then return end
  local lines = {}
  for line in f:lines() do
    if line ~= addr then
      table.insert(lines, line)
    end
  end
  f:close()

  f = io.open(registry, 'w')
  if not f then return end
  for _, line in ipairs(lines) do
    f:write(line .. '\n')
  end
  f:close()
end

vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = register })
vim.api.nvim_create_autocmd('VimLeave', { once = true, callback = unregister })
