local parser = require('blink-bibtex.parser')
local log = require('blink-bibtex.log')

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
    log.debug('file missing, clearing cache', path)
    return {}
  end
  local cached = store[path]
  local mtime = info.mtime and info.mtime.sec or info.mtime
  if cached and cached.mtime == mtime and cached.size == info.size then
    log.debug('using cached entries', { path = path, count = #cached.entries })
    return cached.entries
  end
  log.debug('parsing bibliography file', { path = path })
  local ok, entries = pcall(parser.parse_file, path)
  if not ok then
    log.warn(string.format('Failed to parse %s: %s', path, entries))
    entries = {}
  end
  store[path] = {
    mtime = mtime,
    size = info.size,
    entries = entries,
  }
  log.debug('cached bibliography file', { path = path, count = #entries })
  return entries
end

function M.collect(paths, limit)
  local items = {}
  for _, path in ipairs(paths) do
    local entries = load_file(path)
    log.debug('collecting entries from path', { path = path, count = #entries })
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
  log.debug('cache invalidated', path)
end

return M
