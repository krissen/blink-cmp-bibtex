--- Characterization tests for local bibliography management.

local assert = require('luassert')
local local_bib = require('blink-cmp-bibtex.local_bib')
local helpers = require('tests.helpers')

--- Read a whole file.
--- @param path string
--- @return string
local function read(path)
  local fd = assert(io.open(path, 'r'))
  local content = fd:read('*a')
  fd:close()
  return content
end

local entry = '@article{new2024,\n  title = {A New Entry}\n}'

describe('local_bib.resolve_target', function()
  it('prefers a per-directory target', function()
    helpers.with_tmpdir(function(dir)
      local target = local_bib.resolve_target({
        targets = { [dir] = 'per-dir.bib' },
        target = 'explicit.bib',
        patterns = { 'local.bib' },
      }, dir)
      assert.are.equal(vim.fs.joinpath(dir, 'per-dir.bib'), target)
    end)
  end)

  it('falls back to an explicit target', function()
    helpers.with_tmpdir(function(dir)
      local target = local_bib.resolve_target({ target = 'explicit.bib', patterns = { 'local.bib' } }, dir)
      assert.are.equal(vim.fs.joinpath(dir, 'explicit.bib'), target)
    end)
  end)

  it('keeps an absolute target as-is', function()
    helpers.with_tmpdir(function(dir)
      local absolute = vim.fs.joinpath(dir, 'abs.bib')
      assert.are.equal(absolute, local_bib.resolve_target({ target = absolute }, dir))
    end)
  end)

  it('falls back to the first existing pattern match', function()
    helpers.with_tmpdir(function(dir)
      helpers.write_file(vim.fs.joinpath(dir, 'references.bib'), '')
      local target = local_bib.resolve_target({ patterns = { 'local.bib', 'references.bib' } }, dir)
      assert.are.equal(vim.fs.joinpath(dir, 'references.bib'), target)
    end)
  end)

  it('returns nil when no pattern exists and create_if_missing is off', function()
    helpers.with_tmpdir(function(dir)
      assert.is_nil(local_bib.resolve_target({ patterns = { 'local.bib' } }, dir))
    end)
  end)

  it('uses the first pattern when create_if_missing is on', function()
    helpers.with_tmpdir(function(dir)
      local target = local_bib.resolve_target({
        patterns = { 'local.bib', 'references.bib' },
        create_if_missing = true,
      }, dir)
      assert.are.equal(vim.fs.joinpath(dir, 'local.bib'), target)
    end)
  end)
end)

describe('local_bib.key_exists_in_file', function()
  it('is false for a missing file', function()
    assert.is_false(local_bib.key_exists_in_file(helpers.fixture('does_not_exist.bib'), 'smith2020'))
  end)

  it('finds an existing key', function()
    assert.is_true(local_bib.key_exists_in_file(helpers.fixture('refs.bib'), 'smith2020'))
  end)

  it('finds keys containing magic pattern characters', function()
    assert.is_true(local_bib.key_exists_in_file(helpers.fixture('refs.bib'), 'muller-weber.2021'))
  end)

  it('is false for an absent key', function()
    assert.is_false(local_bib.key_exists_in_file(helpers.fixture('refs.bib'), 'absent2000'))
  end)
end)

describe('local_bib.create_empty_file', function()
  it('creates the file and its parent directories', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'nested', 'deep', 'local.bib')
      assert.is_true(local_bib.create_empty_file(path))
      assert.are.equal('% Local bibliography file\n', read(path))
    end)
  end)
end)

describe('local_bib.append_entry', function()
  it('appends to an empty file without a leading blank line', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      helpers.write_file(path, '')
      assert.is_true(local_bib.append_entry(path, entry))
      assert.are.equal(entry .. '\n', read(path))
    end)
  end)

  it('adds a blank line when the file does not end in a newline', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      helpers.write_file(path, '@book{old,\n  title = {Old}\n}')
      local_bib.append_entry(path, entry)
      assert.is_truthy(read(path):find('}\n\n@article{new2024', 1, true))
    end)
  end)

  it('adds a single newline when the file ends in one newline', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      helpers.write_file(path, '@book{old,\n  title = {Old}\n}\n')
      local_bib.append_entry(path, entry)
      assert.is_truthy(read(path):find('}\n\n@article{new2024', 1, true))
    end)
  end)

  it('adds nothing when the file already ends in a blank line', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      helpers.write_file(path, '@book{old,\n  title = {Old}\n}\n\n')
      local_bib.append_entry(path, entry)
      assert.is_truthy(read(path):find('}\n\n@article{new2024', 1, true))
    end)
  end)

  it('terminates the appended entry with a newline', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      helpers.write_file(path, '')
      local_bib.append_entry(path, entry)
      assert.are.equal('\n', read(path):sub(-1))
    end)
  end)
end)

describe('local_bib.copy_entry', function()
  it('refuses when local_bib is disabled', function()
    assert.is_false(local_bib.copy_entry('new2024', entry, { enabled = false }))
  end)

  it('refuses when no target can be resolved', function()
    helpers.with_tmpdir(function(dir)
      assert.is_false(local_bib.copy_entry('new2024', entry, {
        enabled = true,
        patterns = { 'local.bib' },
        targets = {},
      }))
      assert.are.same({}, vim.fn.readdir(dir))
    end)
  end)

  it('refuses when the target is missing and create_if_missing is off', function()
    helpers.with_tmpdir(function(dir)
      local opts = { enabled = true, target = vim.fs.joinpath(dir, 'local.bib') }
      assert.is_false(local_bib.copy_entry('new2024', entry, opts))
    end)
  end)

  it('creates the target when create_if_missing is on', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      local opts = { enabled = true, target = path, create_if_missing = true, notify_on_add = false }
      assert.is_true(local_bib.copy_entry('new2024', entry, opts))
      assert.is_truthy(read(path):find('@article{new2024', 1, true))
    end)
  end)

  it('refuses a duplicate key when duplicate_check is on', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      helpers.write_file(path, entry .. '\n')
      local opts = { enabled = true, target = path, duplicate_check = true, notify_on_duplicate = false }
      assert.is_false(local_bib.copy_entry('new2024', entry, opts))
      assert.are.equal(entry .. '\n', read(path))
    end)
  end)

  it('appends a duplicate key when duplicate_check is off', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'local.bib')
      helpers.write_file(path, entry .. '\n')
      local opts = { enabled = true, target = path, duplicate_check = false, notify_on_add = false }
      assert.is_true(local_bib.copy_entry('new2024', entry, opts))
      local _, count = read(path):gsub('@article{new2024', '')
      assert.are.equal(2, count)
    end)
  end)
end)
