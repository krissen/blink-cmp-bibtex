--- Shared helpers for the blink-cmp-bibtex test suite.
--- @module tests.helpers

local M = {}

--- Directory containing this file, used to anchor fixture lookups.
--- @type string
local tests_dir = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))

--- Absolute path to a file under tests/fixtures.
--- @param rel string Path relative to tests/fixtures
--- @return string Absolute, normalized path
function M.fixture(rel)
  return vim.fs.normalize(vim.fs.joinpath(tests_dir, 'fixtures', rel))
end

--- Build a fake blink.cmp completion context.
--- @param line string The current line content
--- @param col number|nil Cursor column (defaults to end of line)
--- @param bufnr number|nil Buffer number (defaults to 0)
--- @return table A context table shaped like blink.cmp's
function M.ctx(line, col, bufnr)
  return {
    line = line,
    cursor = { 1, col or #line },
    bufnr = bufnr or 0,
  }
end

--- Run a function inside a fresh temporary directory, cleaning up afterwards.
--- The directory is removed even when the function raises.
--- @param fn function Receives the temporary directory path
--- @return any The value returned by fn
function M.with_tmpdir(fn)
  local dir = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(dir, 'p')
  local ok, result = pcall(fn, dir)
  vim.fn.delete(dir, 'rf')
  if not ok then
    error(result, 0)
  end
  return result
end

--- Write a file, creating parent directories as needed.
--- @param path string Absolute file path
--- @param content string File content
function M.write_file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local fd = assert(io.open(path, 'w'))
  fd:write(content)
  fd:close()
end

--- Create a scratch buffer with the given lines, name and filetype.
--- @param opts table { lines: string[], name: string|nil, filetype: string|nil }
--- @return number The buffer number
function M.make_buf(opts)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.lines or {})
  if opts.name then
    vim.api.nvim_buf_set_name(bufnr, opts.name)
  end
  if opts.filetype then
    vim.api.nvim_set_option_value('filetype', opts.filetype, { buf = bufnr })
  end
  return bufnr
end

return M
