local parser = require('blink-bibtex.parser')

local M = {}
local store = {}

local function stat(path)
  local ok, result = pcall(vim.loop.fs_stat, path)
  if not ok then
    return nil
  end
  return result
end

local function load_file(path)
  local info = stat(path)
  if not info then
    store[path] = nil
    return {}
  end
  local cached = store[path]
  local mtime = info.mtime and info.mtime.sec or info.mtime
  if cached and cached.mtime == mtime and cached.size == info.size then
    return cached.entries
  end
  local ok, entries = pcall(parser.parse_file, path)
  if not ok then
    vim.schedule(function()
      vim.notify(string.format('[blink-bibtex] Failed to parse %s: %s', path, entries), vim.log.levels.WARN)
    end)
    entries = {}
  end
  store[path] = {
    mtime = mtime,
    size = info.size,
    entries = entries,
  }
  return entries
end

function M.collect(paths, limit)
  local items = {}
  for _, path in ipairs(paths) do
    local entries = load_file(path)
    for _, entry in ipairs(entries) do
      items[#items + 1] = {
        key = entry.key,
        entrytype = entry.entrytype,
        fields = entry.fields,
        source_path = path,
      }
      if limit and #items >= limit then
        return items
      end
    end
  end
  return items
end

function M.invalidate(path)
  store[path] = nil
end

return M
