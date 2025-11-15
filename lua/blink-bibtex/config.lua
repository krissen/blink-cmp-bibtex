local M = {}

local defaults = {
  filetypes = { "tex", "plaintex", "markdown", "rmd" },
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
  debug = false,
  ---@type fun(level: integer, message: string)|nil
  log = nil,
}

local options = vim.deepcopy(defaults)

local function merge_tables(base, override)
  if not override then
    return base
  end
  return vim.tbl_deep_extend("force", {}, base, override)
end

function M.setup(opts)
  options = merge_tables(defaults, opts)
  return options
end

function M.extend(opts)
  return merge_tables(options, opts)
end

function M.get()
  return options
end

function M.defaults()
  return defaults
end

return M
