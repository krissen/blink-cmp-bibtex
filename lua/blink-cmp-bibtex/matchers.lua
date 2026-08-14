--- Citation matchers for blink-cmp-bibtex
--- A matcher inspects the text up to the cursor and reports whether the cursor
--- sits inside a citation, and which prefix has been typed so far.
--- This module never requires the config module; it only receives options.
--- @module 'blink-cmp-bibtex.matchers'

local M = {}

--- Result returned by a matcher when the cursor sits inside a citation
--- @class BibtexMatchResult
--- @field prefix string The citation key prefix typed so far
--- @field trigger string|nil Name of the syntax that matched
--- @field command string|nil The citation command that matched, when applicable
--- @field sanitize boolean|nil Override the prefix sanitization for this match

--- A matcher function
--- @alias BibtexMatcherFn fun(text: string, opts: table, ctx: table|nil): BibtexMatchResult|nil

--- A normalized matcher entry
--- @class BibtexMatcherSpec
--- @field name string The matcher name
--- @field match BibtexMatcherFn The matching function
--- @field priority number Lower runs first (default 50)
--- @field sanitize boolean|nil Whether matched prefixes are sanitized
--- @field trigger_characters string[]|nil Characters that should open the menu

--- Default priority for matchers that do not declare one
--- @type number
local DEFAULT_PRIORITY = 50

--- Problems already reported, to keep notifications to one per key per session
--- @type table<string, boolean>
local warned = {}

--- Stand-in filetype key for chains built without a filetype
--- @type string
local NO_FILETYPE = '\0none'

--- Match functions that misbehaved, per filetype they misbehaved in
--- Keyed by the function itself so that a broken override in one filetype
--- never disables the same-named matcher elsewhere. Keys are weak so that
--- matchers belonging to discarded configurations can be collected.
--- @type table<function, table<string, boolean>>
local failed = setmetatable({}, { __mode = 'k' })

--- Report a problem once per key per session
--- @param key string Identifies what the message is about
--- @param message string The message to display
local function warn_once(key, message)
  if warned[key] then
    return
  end
  warned[key] = true
  vim.notify(message, vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
end

--- Whether a match function already misbehaved in this filetype
--- @param match function The match function
--- @param filetype string|nil The buffer filetype
--- @return boolean
local function has_failed(match, filetype)
  local per_filetype = failed[match]
  return per_filetype ~= nil and per_filetype[filetype or NO_FILETYPE] == true
end

--- Remember that a match function misbehaved in this filetype
--- @param match function The match function
--- @param filetype string|nil The buffer filetype
local function mark_failed(match, filetype)
  local per_filetype = failed[match]
  if not per_filetype then
    per_filetype = {}
    failed[match] = per_filetype
  end
  per_filetype[filetype or NO_FILETYPE] = true
end

--- Describe why a matcher result is unusable, if it is
--- @param result any The value a matcher returned
--- @return string|nil A reason, or nil when the result is well formed
local function malformed_reason(result)
  if type(result) ~= 'table' then
    return string.format('returned %s instead of a table', type(result))
  end
  if type(result.prefix) ~= 'string' then
    return string.format('returned a result whose prefix is %s instead of a string', type(result.prefix))
  end
  return nil
end

--- Match LaTeX citation commands in text
--- @param text string The text to search
--- @param opts table Configuration options with citation_commands
--- @return BibtexMatchResult|nil Citation detection result or nil if no match
function M.latex(text, opts)
  local brace_start = text:match('()%{[^{}]*$')
  if not brace_start then
    return nil
  end
  local prefix = text:sub(brace_start + 1)
  local before = text:sub(1, brace_start - 1)
  local cursor = #before
  while cursor > 0 and before:sub(cursor, cursor):match('%s') do
    cursor = cursor - 1
  end
  local function skip_optional()
    while cursor > 0 and before:sub(cursor, cursor) == ']' do
      cursor = cursor - 1
      local depth = 1
      while cursor > 0 and depth > 0 do
        local ch = before:sub(cursor, cursor)
        if ch == '[' then
          depth = depth - 1
        elseif ch == ']' then
          depth = depth + 1
        end
        cursor = cursor - 1
      end
      while cursor > 0 and before:sub(cursor, cursor):match('%s') do
        cursor = cursor - 1
      end
    end
  end
  skip_optional()
  local command_segment = before:sub(1, cursor)
  local command, modifier = command_segment:match('\\([%a@]+)(%*?)$')
  if not command then
    return nil
  end
  for _, allowed in ipairs(opts.citation_commands or {}) do
    if command == allowed then
      return {
        prefix = prefix,
        command = command .. (modifier or ''),
        trigger = 'latex',
      }
    end
  end
  return nil
end

--- Match Pandoc-style citation syntax
--- @param text string The text to search
--- @return BibtexMatchResult|nil Citation detection result or nil if no match
function M.pandoc(text)
  local prefix = text:match('%[@([^%]]*)$')
  if prefix then
    return { prefix = prefix, trigger = 'pandoc' }
  end
  local boundary = text:match('[^%w@]@([%w:_%-%.,]*)$')
  if boundary then
    return { prefix = boundary, trigger = 'pandoc' }
  end
  local line_start = text:match('^@([%w:_%-%.,]*)$')
  if line_start then
    return { prefix = line_start, trigger = 'pandoc' }
  end
  return nil
end

--- Match Typst-style citation syntax
--- @param text string The text to search
--- @return BibtexMatchResult|nil Citation detection result or nil if no match
function M.typst(text)
  -- Match Typst citation patterns: after word/underscore, after non-word, or at line start
  local prefix = text:match('[%w_]@([%w:_%-%.,]*)$') -- match word@abc
  if prefix then
    return { prefix = prefix, trigger = 'typst' }
  end
  local prefix_after_nonword = text:match('[^%w@]@([%w:_%-%.,]*)$') -- match after non-word character
  if prefix_after_nonword then
    return { prefix = prefix_after_nonword, trigger = 'typst' }
  end
  local prefix_at_start = text:match('^@([%w:_%-%.,]*)$') -- match at line start
  if prefix_at_start then
    return { prefix = prefix_at_start, trigger = 'typst' }
  end
  local prefix_cite = text:match('#cite%s*%(%s*<([^>]*)$') -- match #cite(<abc
  if prefix_cite then
    return { prefix = prefix_cite, trigger = 'typst' }
  end
  return nil
end

--- Match GAPDoc `<Cite Key="..."/>` citation syntax
--- GAPDoc keys are used verbatim, so a matched prefix is never sanitized.
--- @param text string The text to search
--- @return BibtexMatchResult|nil Citation detection result or nil if no match
function M.gapdoc(text)
  local prefix = text:match('<Cite%s+[^>]-Key%s*=%s*"([^"]*)$') or text:match("<Cite%s+[^>]-Key%s*=%s*'([^']*)$")
  if prefix then
    return { prefix = prefix, trigger = 'gapdoc', sanitize = false }
  end
  return nil
end

--- Matchers shipped with the plugin, addressable by name from the configuration
--- @type table<string, BibtexMatcherFn>
M.builtin = {
  latex = M.latex,
  pandoc = M.pandoc,
  typst = M.typst,
  gapdoc = M.gapdoc,
}

--- Normalize a configured matcher value into a spec
--- Accepts a function, a spec table, a built-in name, or a boolean.
--- Invalid values are skipped with a single warning per name.
--- @param name string The configuration key the value was found under
--- @param value any The configured value
--- @return BibtexMatcherSpec|nil The normalized spec, or nil when disabled or invalid
function M.normalize(name, value)
  if value == nil or value == false then
    return nil
  end

  local match, extra
  if value == true then
    match = M.builtin[name]
    if not match then
      warn_once(name, string.format("matcher '%s' is enabled but no built-in matcher has that name", name))
      return nil
    end
  elseif type(value) == 'function' then
    match = value
  elseif type(value) == 'string' then
    match = M.builtin[value]
    if not match then
      warn_once(name, string.format("matcher '%s' refers to unknown built-in matcher '%s'", name, value))
      return nil
    end
  elseif type(value) == 'table' then
    extra = value
    if type(value.match) == 'function' then
      match = value.match
    else
      match = M.builtin[name]
      if not match then
        warn_once(name, string.format("matcher '%s' has no match function and no built-in matcher has that name", name))
        return nil
      end
    end
  else
    warn_once(name, string.format("matcher '%s' has unsupported type '%s'", name, type(value)))
    return nil
  end

  return {
    name = name,
    match = match,
    priority = extra and extra.priority or DEFAULT_PRIORITY,
    sanitize = extra and extra.sanitize,
    trigger_characters = extra and extra.trigger_characters,
  }
end

--- Build the ordered matcher chain for a filetype
--- Entries under the filetype key override same-named entries under '*'.
--- @param filetype string|nil The buffer filetype
--- @param opts table Configuration options
--- @return BibtexMatcherSpec[] The matchers to run, in order
function M.chain(filetype, opts)
  local configured = opts and opts.matchers or {}
  local shared = configured['*'] or {}
  local per_filetype = filetype and configured[filetype] or {}

  local values = {}
  for name, value in pairs(shared) do
    values[name] = value
  end
  for name, value in pairs(per_filetype) do
    values[name] = value
  end

  local specs = {}
  for name, value in pairs(values) do
    local spec = M.normalize(name, value)
    if spec then
      specs[#specs + 1] = spec
    end
  end

  table.sort(specs, function(a, b)
    if a.priority ~= b.priority then
      return a.priority < b.priority
    end
    return a.name < b.name
  end)
  return specs
end

--- Run the matcher chain against the text before the cursor
--- @param text string The text up to the cursor
--- @param opts table Configuration options
--- @param ctx table|nil Context with bufnr, filetype, line and col
--- @return BibtexMatchResult|nil result The first match, or nil
--- @return BibtexMatcherSpec|nil spec The matcher that produced the result
function M.detect(text, opts, ctx)
  local filetype = ctx and ctx.filetype
  for _, spec in ipairs(M.chain(filetype, opts)) do
    if not has_failed(spec.match, filetype) then
      local ok, result = pcall(spec.match, text, opts, ctx)
      -- A matcher that errors or answers with something unusable is skipped for
      -- this filetype rather than allowed to break completion downstream.
      local problem
      if not ok then
        problem = string.format('raised an error: %s', result)
      elseif result ~= nil and result ~= false then
        problem = malformed_reason(result)
      end
      if problem then
        mark_failed(spec.match, filetype)
        warn_once(
          string.format('%s@%s', spec.name, filetype or NO_FILETYPE),
          string.format("matcher '%s' %s and is disabled for filetype '%s'", spec.name, problem, filetype or 'unset')
        )
      elseif result then
        return result, spec
      end
    end
  end
  return nil, nil
end

--- Collect the trigger characters declared by a filetype's matcher chain
--- @param filetype string|nil The buffer filetype
--- @param opts table Configuration options
--- @return string[] Deduplicated trigger characters
function M.trigger_characters(filetype, opts)
  local seen = {}
  local characters = {}
  for _, spec in ipairs(M.chain(filetype, opts)) do
    for _, char in ipairs(spec.trigger_characters or {}) do
      if not seen[char] then
        seen[char] = true
        characters[#characters + 1] = char
      end
    end
  end
  return characters
end

--- Internal helpers exposed for testing. Not part of the public API.
M.__test = {
  --- Forget the per-session warning and failed-matcher state.
  reset = function()
    warned = {}
    failed = setmetatable({}, { __mode = 'k' })
  end,
}

return M
