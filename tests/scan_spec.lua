--- Characterization tests for bibliography file discovery.

local assert = require('luassert')
local scan = require('blink-cmp-bibtex.scan')
local helpers = require('tests.helpers')

--- Load a fixture file into a real buffer.
--- @param rel string Path relative to tests/fixtures
--- @param filetype string
--- @return number bufnr
local function open_fixture(rel, filetype)
  local bufnr = vim.fn.bufadd(helpers.fixture(rel))
  vim.fn.bufload(bufnr)
  vim.api.nvim_set_option_value('filetype', filetype, { buf = bufnr })
  return bufnr
end

describe('scan.find_bib_files_from_buffer', function()
  it('returns an empty list for an invalid buffer', function()
    assert.are.same({}, scan.find_bib_files_from_buffer(99999))
  end)

  it('extracts the raw resource name from \\addbibresource', function()
    assert.are.same({ 'bib/refs.bib' }, scan.find_bib_files_from_buffer(open_fixture('project/main.tex', 'tex')))
  end)
end)

describe('scan.resolve_bib_paths', function()
  local fixtures = helpers.fixture('')

  it('resolves \\addbibresource relative to the buffer directory', function()
    local paths = scan.resolve_bib_paths(open_fixture('project/main.tex', 'tex'), {})
    assert.are.same({ helpers.fixture('project/bib/refs.bib') }, paths)
  end)

  it('resolves a scalar YAML bibliography key', function()
    local paths = scan.resolve_bib_paths(open_fixture('project/doc.md', 'markdown'), {})
    assert.are.same({ helpers.fixture('project/bib/refs.bib') }, paths)
  end)

  it('resolves a YAML bibliography list', function()
    local paths = scan.resolve_bib_paths(open_fixture('project/doc_list.md', 'markdown'), {})
    assert.are.same({
      helpers.fixture('project/bib/refs.bib'),
      helpers.fixture('project/shared.bib'),
    }, paths)
  end)

  it('resolves #bibliography() and follows #import statements', function()
    local paths = scan.resolve_bib_paths(open_fixture('project/doc.typ', 'typst'), {})
    -- shared.bib is only declared inside the imported template.typ.
    assert.are.same({
      helpers.fixture('project/bib/refs.bib'),
      helpers.fixture('project/shared.bib'),
    }, paths)
  end)

  it('resolves a GAPDoc <Bibliography> declaration', function()
    -- Deliberate change: doc.xml used to stand in for a buffer without any
    -- bibliography declaration, since its <Bibliography> element was not read.
    local paths = scan.resolve_bib_paths(open_fixture('project/doc.xml', 'xml'), {})
    assert.are.same({ helpers.fixture('project/shared.bib') }, paths)
  end)

  it('finds nothing in a buffer without bibliography declarations', function()
    local bufnr = helpers.make_buf({ lines = { '<Book Name="Empty"><Chapter/></Book>' }, filetype = 'xml' })
    assert.are.same({}, scan.resolve_bib_paths(bufnr, {}))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  describe('with a scratch buffer', function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('resolves absolute entries from opts.files', function()
      local paths = scan.resolve_bib_paths(bufnr, { files = { fixtures .. '/refs.bib' } })
      assert.are.same({ helpers.fixture('refs.bib') }, paths)
    end)

    it('resolves relative opts.files against the root marker directory', function()
      local paths = scan.resolve_bib_paths(bufnr, {
        files = { 'tests/fixtures/refs.bib' },
        root_markers = { '.git' },
      })
      assert.are.same({ helpers.fixture('refs.bib') }, paths)
    end)

    it('expands globs in search_paths', function()
      local paths = scan.resolve_bib_paths(bufnr, {
        search_paths = { 'tests/fixtures/*.bib' },
        root_markers = { '.git' },
      })
      assert.are.same({ helpers.fixture('accents.bib'), helpers.fixture('refs.bib') }, paths)
    end)

    it('accepts a bare string instead of a list', function()
      local paths = scan.resolve_bib_paths(bufnr, { files = fixtures .. '/refs.bib' })
      assert.are.same({ helpers.fixture('refs.bib') }, paths)
    end)

    it('accepts a function returning a list', function()
      local paths = scan.resolve_bib_paths(bufnr, {
        files = function()
          return { fixtures .. '/refs.bib' }
        end,
      })
      assert.are.same({ helpers.fixture('refs.bib') }, paths)
    end)

    it('deduplicates repeated paths', function()
      local paths = scan.resolve_bib_paths(bufnr, {
        files = { fixtures .. '/refs.bib', fixtures .. '/refs.bib' },
      })
      assert.are.same({ helpers.fixture('refs.bib') }, paths)
    end)

    it('filters out non-existent files', function()
      assert.are.same({}, scan.resolve_bib_paths(bufnr, { files = { fixtures .. '/nope.bib' } }))
    end)

    it('filters out directories', function()
      assert.are.same({}, scan.resolve_bib_paths(bufnr, { files = { fixtures .. '/project' } }))
    end)

    it('includes global_files after files', function()
      local paths = scan.resolve_bib_paths(bufnr, {
        files = { fixtures .. '/refs.bib' },
        global_files = { fixtures .. '/accents.bib' },
      })
      assert.are.same({ helpers.fixture('refs.bib'), helpers.fixture('accents.bib') }, paths)
    end)

    it('auto-includes local_bib.target', function()
      local paths = scan.resolve_bib_paths(bufnr, {
        root_markers = { '.git' },
        local_bib = { target = 'tests/fixtures/refs.bib' },
      })
      assert.are.same({ helpers.fixture('refs.bib') }, paths)
    end)
  end)
end)

describe('scan.resolve_option_list', function()
  it('wraps a bare string into a list', function()
    assert.are.same({ 'refs.bib' }, scan.resolve_option_list('refs.bib'))
  end)

  it('passes a list through unchanged', function()
    assert.are.same({ 'a.bib', 'b.bib' }, scan.resolve_option_list({ 'a.bib', 'b.bib' }))
  end)

  it('calls a function option with the given arguments', function()
    local seen
    local result = scan.resolve_option_list(function(bufnr)
      seen = bufnr
      return { 'from-fn.bib' }
    end, 7)
    assert.are.same({ 'from-fn.bib' }, result)
    assert.are.equal(7, seen)
  end)

  it('wraps a function returning a bare string', function()
    assert.are.same(
      { 'one.bib' },
      scan.resolve_option_list(function()
        return 'one.bib'
      end)
    )
  end)

  it('returns an empty list for nil and for a function that raises', function()
    assert.are.same({}, scan.resolve_option_list(nil))
    assert.are.same(
      {},
      scan.resolve_option_list(function()
        error('boom')
      end)
    )
  end)
end)

describe('scan.find_bib_files_from_buffer with GAPDoc declarations', function()
  --- Discover bibliography names from a one-off XML buffer.
  --- @param lines string[]
  --- @return string[]
  local function discover(lines)
    local bufnr = helpers.make_buf({ lines = lines, filetype = 'xml' })
    local resources = scan.find_bib_files_from_buffer(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return resources
  end

  it('appends .bib to a single database name', function()
    assert.are.same({ 'mybib.bib' }, discover({ '<Bibliography Databases="mybib"/>' }))
  end)

  it('splits several comma-separated databases and trims them', function()
    assert.are.same({ 'gapdoc.bib', 'mybib.bib' }, discover({ '<Bibliography Databases="gapdoc, mybib"/>' }))
  end)

  it('reads a single-quoted attribute', function()
    assert.are.same({ 'mybib.bib' }, discover({ "<Bibliography Databases='mybib'/>" }))
  end)

  it('ignores the optional Style attribute, before or after Databases', function()
    assert.are.same({ 'mybib.bib' }, discover({ '<Bibliography Databases="mybib" Style="alpha"/>' }))
    assert.are.same({ 'mybib.bib' }, discover({ '<Bibliography Style="alpha" Databases="mybib"/>' }))
  end)

  it('reads a declaration split across lines', function()
    assert.are.same({ 'mybib.bib' }, discover({ '<Bibliography', '   Databases="mybib"/>' }))
  end)

  it('reads several declarations in one document', function()
    assert.are.same(
      { 'first.bib', 'second.bib' },
      discover({ '<Bibliography Databases="first"/>', '<Bibliography Databases="second"/>' })
    )
  end)

  it('keeps a database name that already carries a path', function()
    assert.are.same({ 'bib/refs.bib' }, discover({ '<Bibliography Databases="bib/refs"/>' }))
  end)

  it('skips BibXMLext databases, which are named with their .xml extension', function()
    assert.are.same({ 'mybib.bib' }, discover({ '<Bibliography Databases="mybib, gapdoc.xml"/>' }))
  end)

  it('does not match a different element with a similar name', function()
    assert.are.same({}, discover({ '<BibliographyIndex Databases="mybib"/>' }))
  end)

  it('does not match a Cite element', function()
    assert.are.same({}, discover({ '<Cite Key="mybib"/>' }))
  end)

  it('does not read a Databases attribute from a following element', function()
    assert.are.same({}, discover({ '<Bibliography/> <Other Databases="mybib"/>' }))
  end)

  it('appends .bib to a dotted name, which GAPDoc treats as extensionless', function()
    assert.are.same({ 'references.v2.bib' }, discover({ '<Bibliography Databases="references.v2"/>' }))
  end)

  it('appends .bib even to a name that already spells it out', function()
    -- Characterizes the rule rather than second-guessing it: GAPDoc itself
    -- appends .bib to whatever is written, so 'refs.bib' names refs.bib.bib.
    assert.are.same({ 'refs.bib.bib' }, discover({ '<Bibliography Databases="refs.bib"/>' }))
  end)

  it('ignores a declaration inside an XML comment', function()
    assert.are.same({}, discover({ '<!-- <Bibliography Databases="old"/> -->' }))
  end)

  it('ignores a declaration inside a comment spanning several lines', function()
    assert.are.same({}, discover({ '<!--', '  <Bibliography Databases="old"/>', '-->' }))
  end)

  it('still reads a live declaration following a commented-out one', function()
    assert.are.same(
      { 'current.bib' },
      discover({ '<!-- <Bibliography Databases="old"/> -->', '<Bibliography Databases="current"/>' })
    )
  end)

  it('ignores a declaration after an unterminated comment opener', function()
    assert.are.same({}, discover({ '<!-- retired', '<Bibliography Databases="old"/>' }))
  end)

  it('does not join the buffer when no declaration marker is present', function()
    -- The extractor runs for every filetype, so the scan must stay cheap in
    -- buffers that cannot contain a declaration at all.
    -- Counting the joins is the only way to observe the guard from outside,
    -- so table.concat is stubbed for the duration of this test and restored
    -- below even when an assertion fails.
    local original = table.concat
    local calls = 0
    --- @diagnostic disable-next-line: duplicate-set-field
    table.concat = function(...) -- luacheck: ignore
      calls = calls + 1
      return original(...)
    end
    local ok, err = pcall(function()
      assert.are.same({ 'bib/refs.bib' }, discover({ '\\addbibresource{bib/refs.bib}' }))
      assert.are.equal(0, calls, 'joined the buffer without a <Bibliography marker')
      discover({ '<Bibliography Databases="mybib"/>' })
      assert.is_true(calls > 0, 'never joined the buffer despite a marker')
    end)
    table.concat = original -- luacheck: ignore
    assert.is_true(ok, tostring(err))
  end)
end)
