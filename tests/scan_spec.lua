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

  it('finds nothing in a buffer without bibliography declarations', function()
    assert.are.same({}, scan.resolve_bib_paths(open_fixture('project/doc.xml', 'xml'), {}))
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
