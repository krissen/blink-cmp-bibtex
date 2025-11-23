--- Configuration module for blink-cmp-bibtex
--- Manages default settings and allows customization through setup() and extend()
--- @module blink-cmp-bibtex.config

local M = {}

--- Default configuration options
--- @type table
local defaults = {
  filetypes = { "tex", "plaintex", "markdown", "rmd", "typst" },
  files = {},
  search_paths = {},
  root_markers = { ".git", "latexmkrc", "texmf.cnf" },
  citation_commands = {
    "cite", "parencite", "textcite", "footcite", "smartcite",
    "autocite", "nocite", "citep", "citet",
  },
  pandoc_triggers = { "[@", "@" },
  preview_style = "apa",
  max_entries = 4000,
}

--- Deep copy a table to avoid mutation
--- @param tbl table The table to copy
--- @return table A deep copy of the table
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

--- Merge two tables with override taking precedence
--- @param base table The base table
--- @param override table|nil The override table
--- @return table The merged table
local function merge_tables(base, override)
  if not override then
    return base
  end
  return vim.tbl_deep_extend("force", {}, base, override)
end

--- Setup configuration with custom options
--- @param opts table|nil User-provided configuration options
--- @return table The final merged configuration
function M.setup(opts)
  options = merge_tables(defaults, opts)
  return options
end

--- Extend current options with additional overrides
--- @param opts table|nil Additional options to merge
--- @return table The extended configuration
function M.extend(opts)
  return merge_tables(options, opts)
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
