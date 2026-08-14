--- Configuration module for blink-cmp-bibtex
--- Manages default settings and allows customization through setup() and extend()
--- @module 'blink-cmp-bibtex.config'

local discovery = require('blink-cmp-bibtex.discovery')
local registry = require('blink-cmp-bibtex.registry')
local matchers = require('blink-cmp-bibtex.matchers')

local M = {}

--- Default configuration options
--- @type table
local defaults = {
  filetypes = { 'tex', 'plaintex', 'markdown', 'rmd', 'typst' },
  files = {},
  global_files = {},
  search_paths = {},
  root_markers = { '.git', 'latexmkrc', 'texmf.cnf' },
  citation_commands = {
    'cite',
    'parencite',
    'textcite',
    'footcite',
    'smartcite',
    'autocite',
    'nocite',
    'citep',
    'citet',
  },
  -- Bibliography discovery hooks per filetype. Entries under a filetype key
  -- override same-named entries under '*'. Unlike the matchers, every shipped
  -- hook sits under '*', because buffer discovery is filetype agnostic.
  discovery = vim.deepcopy(discovery.defaults),
  -- Citation matchers per filetype. Entries under a filetype key override
  -- same-named entries under '*'. The shipped dispatch and the accepted entry
  -- forms both live in matchers.lua, which owns this default.
  matchers = vim.deepcopy(matchers.defaults),
  preview_style = 'apa',
  source_indicator = true,
  max_entries = 4000,
  local_bib = {
    enabled = false,
    target = nil,
    targets = {},
    patterns = { 'local.bib', 'references.bib' },
    auto_add = false,
    notify_on_add = true,
    notify_on_duplicate = false,
    create_if_missing = false,
    duplicate_check = true,
  },
}

--- Deep copy a value, so that callers cannot mutate what they were given
--- Anything that is not a table is returned as-is, which is what lets the
--- option repair below copy a default without knowing its shape.
--- @param tbl any The value to copy
--- @return any A deep copy, for a table, or the value itself
local function deep_copy(tbl)
  if type(tbl) ~= 'table' then
    return tbl
  end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = type(v) == 'table' and deep_copy(v) or v
  end
  return copy
end

local options = deep_copy(defaults)

--- Whether a value is a list, and therefore replaced rather than merged
--- @param value any The value to inspect
--- @return boolean
local function is_list(value)
  if type(value) ~= 'table' or next(value) == nil then
    -- An empty table is ambiguous; treating it as a map keeps `local_bib = {}`
    -- from wiping the nested defaults, while an empty override against a
    -- non-empty list still replaces that list.
    return false
  end
  local islist = vim.islist or vim.tbl_islist
  return islist(value)
end

--- Deep merge two tables with override taking precedence
--- Maps are merged key by key; lists are replaced wholesale, so a user who
--- configures three citation_commands does not inherit the remaining defaults.
--- @param base table The base table
--- @param override table|nil The override table
--- @return table The merged table
local function merge_tables(base, override)
  if not override then
    return base
  end
  local result = deep_copy(base)
  for key, value in pairs(override) do
    local current = result[key]
    if type(value) == 'table' and type(current) == 'table' and not is_list(value) and not is_list(current) then
      result[key] = merge_tables(current, value)
    else
      result[key] = type(value) == 'table' and deep_copy(value) or value
    end
  end
  return result
end

--- How each option that must not be a scalar is repaired when it is one
--- 'registry' options accept true (the shipped entries) and false (none of
--- them) as shorthands; every other option only ever holds a table, except the
--- path options, which have always accepted a string or a function as well.
--- @type table<string, string>
local option_kinds = {
  matchers = 'registry',
  discovery = 'registry',
  local_bib = 'map',
  filetypes = 'list',
  citation_commands = 'list',
  root_markers = 'list',
  files = 'path',
  global_files = 'path',
  search_paths = 'path',
}

--- Replace option values of a type the plugin cannot use
--- Everything downstream indexes these values, iterates them or takes their
--- length, so a scalar left in place would crash a completion round, the
--- scanner or the health check. Repairing them here means each consumer can
--- keep reading the option directly, and the user is told once what happened.
--- @param resolved table The merged options, modified in place
--- @return table The same table
local function sanitize(resolved)
  for name, kind in pairs(option_kinds) do
    local value = resolved[name]
    local usable = type(value) == 'table'
      or (kind == 'path' and (type(value) == 'string' or type(value) == 'function'))
      -- Only false passes through, disabling the registry; true means "what the
      -- plugin ships" and is expanded into the default below.
      or (kind == 'registry' and value == false)

    if not usable and value ~= nil then
      if kind == 'registry' and value == true then
        -- Reads as "use what the plugin ships", which is what the default is.
        resolved[name] = deep_copy(defaults[name])
      else
        registry.warn_once(
          'config',
          name,
          string.format("option '%s' is %s, which cannot be used; the default applies", name, type(value))
        )
        resolved[name] = deep_copy(defaults[name])
      end
    end
  end
  return resolved
end

--- Setup configuration with custom options
--- @param opts table|nil User-provided configuration options
--- @return table The final merged configuration
function M.setup(opts)
  options = sanitize(merge_tables(defaults, opts))
  return options
end

--- Extend current options with additional overrides
--- @param opts table|nil Additional options to merge
--- @return table The extended configuration
function M.extend(opts)
  return sanitize(merge_tables(options, opts))
end

--- Get the current configuration
--- @return table Current configuration options
function M.get()
  return options
end

--- Get the default configuration
--- @return table Default configuration options
function M.defaults()
  return defaults
end

return M
