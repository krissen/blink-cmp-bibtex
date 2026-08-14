--- Shared bookkeeping for the plugin's extension points
--- Both the matcher chain and the discovery chain run user-supplied functions,
--- and both must survive a misbehaving one: report the problem once, then stop
--- calling that function in the filetype where it misbehaved. This module holds
--- that state so the two chains cannot drift apart in how they handle it.
--- @module 'blink-cmp-bibtex.registry'

local M = {}

--- Stand-in filetype key for chains built without a filetype
--- @type string
M.NO_FILETYPE = '\0none'

--- Problems already reported, to keep notifications to one per key per session
--- @type table<string, boolean>
local warned = {}

--- Functions that misbehaved, per filetype they misbehaved in
--- Keyed by the function itself so that a broken override in one filetype never
--- disables the same-named entry elsewhere. Keys are weak so that functions
--- belonging to discarded configurations can be collected.
--- @type table<function, table<string, boolean>>
local failed = setmetatable({}, { __mode = 'k' })

--- Report a problem once per key per session
--- The consumer namespaces the key, so a matcher and a discovery hook that
--- happen to share a name do not silence each other's warnings.
--- @param consumer string Which registry is reporting, e.g. 'matcher'
--- @param key string Identifies what the message is about within that registry
--- @param message string The message to display
function M.warn_once(consumer, key, message)
  local namespaced = consumer .. ':' .. key
  if warned[namespaced] then
    return
  end
  warned[namespaced] = true
  vim.notify(message, vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
end

--- Whether a function already misbehaved in this filetype
--- @param fn function The registered function
--- @param filetype string|nil The buffer filetype
--- @return boolean
function M.has_failed(fn, filetype)
  local per_filetype = failed[fn]
  return per_filetype ~= nil and per_filetype[filetype or M.NO_FILETYPE] == true
end

--- Remember that a function misbehaved in this filetype
--- @param fn function The registered function
--- @param filetype string|nil The buffer filetype
function M.mark_failed(fn, filetype)
  local per_filetype = failed[fn]
  if not per_filetype then
    per_filetype = {}
    failed[fn] = per_filetype
  end
  per_filetype[filetype or M.NO_FILETYPE] = true
end

--- Render an arbitrary error value as text
--- A registered function may throw anything, including a table whose __tostring
--- itself raises, so every conversion attempt is protected.
--- @param err any The value that was thrown
--- @return string
function M.describe_error(err)
  if type(err) == 'string' then
    return err
  end
  local ok, rendered = pcall(vim.inspect, err)
  if ok and type(rendered) == 'string' then
    return rendered
  end
  ok, rendered = pcall(tostring, err)
  if ok and type(rendered) == 'string' then
    return rendered
  end
  return '<unprintable error>'
end

--- Forget the per-session warning and failure state
--- Exposed for tests, which need each case to start from a clean slate.
function M.reset()
  warned = {}
  failed = setmetatable({}, { __mode = 'k' })
end

return M
