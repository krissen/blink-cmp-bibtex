--- Cache module for blink-cmp-bibtex
--- Provides memoized storage of parsed BibTeX entries with modification time tracking
--- @module blink-cmp-bibtex.cache

local parser = require('blink-cmp-bibtex.parser')

local M = {}
--- Cache storage keyed by file path
--- @type table<string, {mtime: number, size: number, entries: table[]}>
local store = {}

--- Notify user of warnings
--- @param message string The warning message to display
local function notify(message)
  if not (vim and vim.notify) then
    return
  end
  vim.schedule(function()
    vim.notify(message, vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
  end)
end

--- Get file statistics for a given path
--- @param path string The file path to check
--- @return table|nil File stat information or nil if unavailable
local function stat(path)
  local uv = vim.uv or vim.loop
  local ok, result = pcall(uv.fs_stat, path)
  if not ok then
    return nil
  end
  return result
end

--- Load and cache BibTeX entries from a file
--- @param path string The file path to load
--- @return table[] List of parsed BibTeX entries
local function load_file(path)
  local info = stat(path)
  if not info then
    store[path] = nil
    return {}
  end
  local cached = store[path]
  local mtime = info.mtime and (info.mtime.sec or info.mtime) or nil
  if cached and cached.mtime == mtime and cached.size == info.size then
    return cached.entries
  end
  local ok, entries = pcall(parser.parse_file, path)
  if not ok then
    notify(string.format('Failed to parse %s: %s', path, entries))
    entries = {}
  end
  store[path] = {
    mtime = mtime,
    size = info.size,
    entries = entries,
  }
  return entries
end

--- Collect all entries from multiple BibTeX files
--- @param paths string[] List of file paths to collect from
--- @param limit number|nil Optional maximum number of entries to collect
--- @return table[] List of all collected entries
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

--- Invalidate cache for a specific file path
--- @param path string The file path to invalidate
function M.invalidate(path)
  store[path] = nil
end

return M
