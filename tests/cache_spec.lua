--- Characterization tests for the mtime-based entry cache.

local assert = require('luassert')
local cache = require('blink-cmp-bibtex.cache')
local parser = require('blink-cmp-bibtex.parser')
local helpers = require('tests.helpers')

--- Count parser.parse_file calls while running fn.
--- @param fn function
--- @return number The number of calls made
local function count_parses(fn)
  local original = parser.parse_file
  local calls = 0
  -- rawset installs the spy without redeclaring the module's own field.
  rawset(parser, 'parse_file', function(...)
    calls = calls + 1
    return original(...)
  end)
  local ok, err = pcall(fn)
  rawset(parser, 'parse_file', original)
  if not ok then
    error(err, 0)
  end
  return calls
end

describe('cache.collect', function()
  local refs = helpers.fixture('refs.bib')

  before_each(function()
    cache.invalidate(refs)
  end)

  it('returns entries annotated with source_path and raw text', function()
    local entries = cache.collect({ refs })
    assert.are.equal(4, #entries)
    for _, entry in ipairs(entries) do
      assert.are.equal(refs, entry.source_path)
      assert.is_string(entry.raw)
      assert.is_string(entry.key)
      assert.is_table(entry.fields)
    end
  end)

  it('concatenates entries from several files in path order', function()
    local entries = cache.collect({ refs, helpers.fixture('accents.bib') })
    assert.are.equal(9, #entries)
    assert.are.equal('smith2020', entries[1].key)
    assert.are.equal('umlaut2020', entries[5].key)
  end)

  it('truncates at the given limit', function()
    assert.are.equal(2, #cache.collect({ refs }, 2))
  end)

  it('returns an empty list for a missing file', function()
    assert.are.same({}, cache.collect({ helpers.fixture('does_not_exist.bib') }))
  end)

  it('parses a file only once across repeated calls', function()
    local calls = count_parses(function()
      cache.collect({ refs })
      cache.collect({ refs })
      cache.collect({ refs })
    end)
    assert.are.equal(1, calls)
  end)

  it('re-parses after the file is modified', function()
    helpers.with_tmpdir(function(dir)
      local path = vim.fs.joinpath(dir, 'tmp.bib')
      helpers.write_file(path, '@article{one,\n  title = {One}\n}\n')

      local first = cache.collect({ path })
      assert.are.same({ 'one' }, { first[1].key })

      -- Bump mtime explicitly: writing within the same second would otherwise
      -- leave the cached stat unchanged on filesystems with 1s granularity.
      helpers.write_file(path, '@article{two,\n  title = {Two}\n}\n')
      local stat = assert(vim.uv.fs_stat(path))
      vim.uv.fs_utime(path, stat.atime.sec + 10, stat.mtime.sec + 10)

      local calls = count_parses(function()
        local second = cache.collect({ path })
        assert.are.same({ 'two' }, { second[1].key })
      end)
      assert.are.equal(1, calls)
      cache.invalidate(path)
    end)
  end)

  it('re-parses after invalidate', function()
    cache.collect({ refs })
    local calls = count_parses(function()
      cache.invalidate(refs)
      cache.collect({ refs })
    end)
    assert.are.equal(1, calls)
  end)
end)
