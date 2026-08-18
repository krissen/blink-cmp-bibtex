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

describe('scan.find_bib_files_from_buffer built-in order', function()
  -- Pins the behavior the discovery hooks must reproduce: which syntaxes are
  -- read, in which order, and which names come back with an extension.

  it('returns raw names, LaTeX before YAML, for a buffer declaring both', function()
    local bufnr = open_fixture('project/mixed.md', 'markdown')
    assert.are.same({ 'bib/refs.bib', 'shared.bib' }, scan.find_bib_files_from_buffer(bufnr))
  end)

  it('appends .bib to extensionless LaTeX, YAML and Typst names', function()
    local bufnr = helpers.make_buf({
      lines = {
        '---',
        'bibliography: fromyaml',
        '---',
        '\\addbibresource{fromlatex}',
        '#bibliography("fromtypst")',
      },
      filetype = 'markdown',
    })
    assert.are.same({ 'fromlatex.bib', 'fromyaml.bib', 'fromtypst.bib' }, scan.find_bib_files_from_buffer(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('leaves a dotted GAPDoc name alone, which already carries its extension', function()
    local bufnr = helpers.make_buf({ lines = { '<Bibliography Databases="refs.v2"/>' }, filetype = 'xml' })
    assert.are.same({ 'refs.v2.bib' }, scan.find_bib_files_from_buffer(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('resolves a Typst import relative to the imported file, not the importer', function()
    helpers.with_tmpdir(function(dir)
      local nested = vim.fs.joinpath(dir, 'nested')
      helpers.write_file(vim.fs.joinpath(nested, 'template.typ'), '#bibliography("refs.bib")\n')
      helpers.write_file(vim.fs.joinpath(dir, 'main.typ'), '#import "nested/template.typ": *\n')
      local bufnr = vim.fn.bufadd(vim.fs.joinpath(dir, 'main.typ'))
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_option_value('filetype', 'typst', { buf = bufnr })
      -- Resolved, since the import path is derived from the buffer name and the
      -- temporary directory reaches it through a symlink on macOS.
      local expected = vim.fs.joinpath(vim.fs.normalize(vim.fn.resolve(nested)), 'refs.bib')
      assert.are.same({ expected }, scan.find_bib_files_from_buffer(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  it('passes an absolute Typst bibliography path through unchanged', function()
    helpers.with_tmpdir(function(dir)
      local absolute = vim.fs.joinpath(dir, 'refs.bib')
      local bufnr = helpers.make_buf({
        lines = { string.format('#bibliography("%s")', absolute) },
        filetype = 'typst',
      })
      assert.are.same({ absolute }, scan.find_bib_files_from_buffer(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
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

  it('resolves every declaration of a buffer that mixes syntaxes', function()
    -- Pins that discovery still runs when no options are configured at all.
    local paths = scan.resolve_bib_paths(open_fixture('project/mixed.md', 'markdown'), {})
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

  describe('inactive regions', function()
    -- A declaration inside a region an XML processor does not read as markup
    -- names a bibliography that is not in use, whatever kind of region it is.
    local regions = {
      { name = 'a comment', open = '<!--', close = '-->' },
      { name = 'a CDATA section', open = '<![CDATA[', close = ']]>' },
      { name = 'a processing instruction', open = '<?gapdoc', close = '?>' },
      {
        name = 'a DOCTYPE internal subset',
        open = '<!DOCTYPE Book SYSTEM "gapdoc.dtd" [',
        close = ']>',
        -- An entity declaration parks the markup as replacement text, which is
        -- inert until something references the entity.
        wrapped = '<!DOCTYPE Book SYSTEM "gapdoc.dtd" [ <!ENTITY old "<Bibliography Databases=\'old\'/>"> ]>',
      },
    }

    for _, region in ipairs(regions) do
      local wrapped = region.wrapped or (region.open .. ' <Bibliography Databases="old"/> ' .. region.close)

      it('ignores a declaration inside ' .. region.name, function()
        assert.are.same({}, discover({ wrapped }))
      end)

      it('ignores a declaration inside ' .. region.name .. ' spanning several lines', function()
        assert.are.same({}, discover({ region.open, '  <Bibliography Databases="old"/>', region.close }))
      end)

      it('still reads a live declaration before ' .. region.name, function()
        assert.are.same({ 'current.bib' }, discover({ '<Bibliography Databases="current"/>', wrapped }))
      end)

      it('still reads a live declaration after ' .. region.name, function()
        assert.are.same({ 'current.bib' }, discover({ wrapped, '<Bibliography Databases="current"/>' }))
      end)

      it('still reads live declarations on both sides of ' .. region.name, function()
        assert.are.same(
          { 'first.bib', 'second.bib' },
          discover({ '<Bibliography Databases="first"/>', wrapped, '<Bibliography Databases="second"/>' })
        )
      end)

      it('treats the rest of the document as inactive after an unterminated ' .. region.name, function()
        -- Documented behavior: an opener without its closer runs to the end of
        -- the document, which is what the region looks like while it is typed.
        assert.are.same({}, discover({ region.open .. ' retired', '<Bibliography Databases="old"/>' }))
      end)
    end

    it('reads a declaration before an unterminated region', function()
      assert.are.same({ 'current.bib' }, discover({ '<Bibliography Databases="current"/>', '<!-- retired' }))
    end)

    it('is unaffected by the XML declaration of a normal document', function()
      assert.are.same(
        { 'mybib.bib' },
        discover({ '<?xml version="1.0" encoding="UTF-8"?>', '<Bibliography Databases="mybib"/>' })
      )
    end)

    it('is unaffected by a DOCTYPE without an internal subset', function()
      assert.are.same(
        { 'mybib.bib' },
        discover({ '<!DOCTYPE Book SYSTEM "gapdoc.dtd">', '<Bibliography Databases="mybib"/>' })
      )
    end)

    it('does not let a subset-less DOCTYPE reach a later name containing brackets', function()
      -- The internal-subset pattern must not scan past the DOCTYPE's own '>'
      -- looking for a ']' that belongs to something else entirely.
      assert.are.same(
        { 'bib[1].bib' },
        discover({ '<!DOCTYPE Book SYSTEM "gapdoc.dtd">', '<Bibliography Databases="bib[1]"/>' })
      )
    end)

    it('reads a declaration in a document with a full GAPDoc prologue', function()
      assert.are.same(
        { 'manual.bib' },
        discover({
          '<?xml version="1.0" encoding="UTF-8"?>',
          '<!DOCTYPE Book SYSTEM "gapdoc.dtd" [',
          '  <!ENTITY GAP "<Package>GAP</Package>">',
          ']>',
          '<Book Name="Manual">',
          '  <Bibliography Databases="manual"/>',
          '</Book>',
        })
      )
    end)
  end)

  describe('character references', function()
    local cases = {
      { name = 'a named entity', written = 'references&amp;notes', expected = 'references&notes.bib' },
      { name = 'a decimal reference', written = 'references&#38;notes', expected = 'references&notes.bib' },
      { name = 'a lowercase hex reference', written = 'references&#x26;notes', expected = 'references&notes.bib' },
      { name = 'an uppercase hex reference', written = 'references&#X26;notes', expected = 'references&notes.bib' },
      { name = 'an apostrophe entity', written = 'o&apos;neill', expected = "o'neill.bib" },
      { name = 'a quote entity', written = 'say&quot;what', expected = 'say"what.bib' },
      { name = 'a non-ASCII reference', written = 'caf&#233;', expected = 'caf\u{e9}.bib' },
    }

    for _, case in ipairs(cases) do
      it('decodes ' .. case.name, function()
        assert.are.same({ case.expected }, discover({ '<Bibliography Databases="' .. case.written .. '"/>' }))
      end)
    end

    it('leaves an undeclared entity as written', function()
      assert.are.same({ 'refs&custom;more.bib' }, discover({ '<Bibliography Databases="refs&custom;more"/>' }))
    end)

    it('decodes before splitting, so an encoded comma separates names', function()
      -- An XML processor resolves the reference first, and GAPDoc then splits
      -- the decoded value, so this names two databases rather than one.
      assert.are.same({ 'first.bib', 'second.bib' }, discover({ '<Bibliography Databases="first&#44;second"/>' }))
    end)
  end)

  it('returns declarations in source order regardless of quote style', function()
    assert.are.same(
      { 'first.bib', 'second.bib', 'third.bib', 'fourth.bib' },
      discover({
        "<Bibliography Databases='first'/>",
        '<Bibliography Databases="second"/>',
        "<Bibliography Databases='third'/>",
        '<Bibliography Databases="fourth"/>',
      })
    )
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

describe('scan discovery hooks', function()
  local discovery = require('blink-cmp-bibtex.discovery')

  before_each(function()
    discovery.__test.reset()
  end)

  --- Options carrying a single user hook alongside the shipped ones.
  --- @param entry any The configured value for the hook
  --- @param filetype string|nil The filetype key to register it under
  --- @return table
  local function with_hook(entry, filetype)
    local opts = { discovery = vim.deepcopy(discovery.defaults) }
    if filetype then
      opts.discovery[filetype] = { mine = entry }
    else
      opts.discovery['*'].mine = entry
    end
    return opts
  end

  it('resolves a relative path from a user hook against the buffer directory', function()
    local bufnr = vim.fn.bufadd(helpers.fixture('project/doc.md'))
    vim.fn.bufload(bufnr)
    local opts = with_hook(function()
      return 'bib/refs.bib'
    end)
    -- The YAML declaration in the fixture resolves to the same file.
    assert.are.same({ helpers.fixture('project/bib/refs.bib') }, scan.resolve_bib_paths(bufnr, opts))
  end)

  it('passes an absolute path from a user hook through', function()
    local bufnr = helpers.make_buf({ lines = { '' }, filetype = 'markdown' })
    local opts = with_hook(function()
      return helpers.fixture('refs.bib')
    end)
    assert.are.same({ helpers.fixture('refs.bib') }, scan.resolve_bib_paths(bufnr, opts))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('gives the hook a context describing the buffer', function()
    local seen
    local bufnr = vim.fn.bufadd(helpers.fixture('project/doc.md'))
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
    scan.find_bib_files_from_buffer(
      bufnr,
      with_hook(function(context)
        seen = context
        return nil
      end)
    )
    assert.are.equal(bufnr, seen.bufnr)
    assert.are.equal('markdown', seen.filetype)
    assert.are.equal(helpers.fixture('project'), vim.fs.normalize(seen.dir))
    assert.is_true(#seen.lines > 0)
  end)

  it('gives the hook the project root found through the root markers', function()
    helpers.with_tmpdir(function(dir)
      local root = vim.fs.normalize(dir)
      vim.fn.mkdir(vim.fs.joinpath(root, '.git'), 'p')
      helpers.write_file(vim.fs.joinpath(root, 'doc/main.tex'), '')
      local bufnr = vim.fn.bufadd(vim.fs.joinpath(root, 'doc/main.tex'))
      vim.fn.bufload(bufnr)
      local seen
      local opts = with_hook(function(context)
        seen = context
        return nil
      end)
      opts.root_markers = { '.git' }
      scan.find_bib_files_from_buffer(bufnr, opts)
      -- Neovim resolves the buffer name, so the root arrives with symlinks
      -- resolved as well; on macOS the temporary directory is one.
      assert.are.equal(vim.fs.normalize(vim.fn.resolve(root)), vim.fs.normalize(seen.root))
    end)
  end)

  it('drops only the disabled built-in for the filetype it is disabled in', function()
    local opts = { discovery = vim.deepcopy(discovery.defaults) }
    opts.discovery.markdown = { yaml = false }
    local bufnr = open_fixture('project/mixed.md', 'markdown')
    -- The LaTeX declaration survives; only the YAML one is dropped.
    assert.are.same({ 'bib/refs.bib' }, scan.find_bib_files_from_buffer(bufnr, opts))
    assert.are.same({ 'bib/refs.bib', 'shared.bib' }, scan.find_bib_files_from_buffer(bufnr, { discovery = nil }))
  end)

  it('resolves the bibliography of the GAP package a source file belongs to', function()
    helpers.with_tmpdir(function(dir)
      local root = vim.fs.joinpath(vim.fs.normalize(dir), 'pkg')
      helpers.write_file(vim.fs.joinpath(root, 'PackageInfo.g'), 'PackageName := "LocalNR",\n')
      helpers.write_file(vim.fs.joinpath(root, 'doc/_main.xml'), '<Bibliography Databases="manual"/>\n')
      helpers.write_file(vim.fs.joinpath(root, 'doc/manual.bib'), '@book{key, title = {T}}\n')
      helpers.write_file(vim.fs.joinpath(root, 'lib/foo.gd'), '#! @Chapter Local\n')
      local bufnr = vim.fn.bufadd(vim.fs.joinpath(root, 'lib/foo.gd'))
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_option_value('filetype', 'gap', { buf = bufnr })
      local resolved = scan.resolve_bib_paths(bufnr, {})
      assert.are.equal(1, #resolved)
      assert.is_truthy(resolved[1]:find('/pkg/doc/manual.bib', 1, true))
    end)
  end)

  it('discovers nothing from the buffer when discovery is configured as empty', function()
    local bufnr = open_fixture('project/mixed.md', 'markdown')
    assert.are.same({}, scan.find_bib_files_from_buffer(bufnr, { discovery = {} }))
    -- Explicitly configured files are unaffected.
    assert.are.same(
      { helpers.fixture('refs.bib') },
      scan.resolve_bib_paths(bufnr, { discovery = {}, files = { helpers.fixture('refs.bib') } })
    )
  end)
end)

describe('scan.resolve_bib_sources', function()
  local fixtures = helpers.fixture('')

  --- Find the source for a path, failing the test when it is absent.
  --- @param sources table[] The sources returned by resolve_bib_sources
  --- @param path string The normalized absolute path
  --- @return table
  local function source_for(sources, path)
    for _, source in ipairs(sources) do
      if source.path == path then
        return source
      end
    end
    error('no source for ' .. path)
  end

  it('records the hook and line of a LaTeX declaration', function()
    local sources = scan.resolve_bib_sources(open_fixture('project/main.tex', 'tex'), {})
    local source = source_for(sources, helpers.fixture('project/bib/refs.bib'))
    assert.is_true(source.exists)
    assert.is_false(source.is_dir)
    assert.are.same({ { kind = 'buffer', detail = 'bib/refs.bib', hook = 'latex', line = 3 } }, source.origins)
  end)

  it('records the declaring file of a Typst bibliography reached through an import', function()
    local sources = scan.resolve_bib_sources(open_fixture('project/doc.typ', 'typst'), {})
    local source = source_for(sources, helpers.fixture('project/shared.bib'))
    local origin = source.origins[1]
    assert.are.equal('buffer', origin.kind)
    assert.are.equal('typst', origin.hook)
    assert.are.equal(8, origin.line)
    assert.are.equal(helpers.fixture('project/template.typ'), vim.fs.normalize(origin.file))
  end)

  it('records the hook but no position for a GAPDoc declaration', function()
    local sources = scan.resolve_bib_sources(open_fixture('project/doc.xml', 'xml'), {})
    local origin = source_for(sources, helpers.fixture('project/shared.bib')).origins[1]
    assert.are.same({ kind = 'buffer', detail = 'shared.bib', hook = 'gapdoc' }, origin)
  end)

  describe('with a scratch buffer', function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('records the option a path was configured in', function()
      local sources = scan.resolve_bib_sources(bufnr, {
        files = { fixtures .. '/refs.bib' },
        global_files = { fixtures .. '/accents.bib' },
      })
      assert.are.same({
        { kind = 'files', detail = fixtures .. '/refs.bib' },
      }, source_for(sources, helpers.fixture('refs.bib')).origins)
      assert.are.same({
        { kind = 'global_files', detail = fixtures .. '/accents.bib' },
      }, source_for(sources, helpers.fixture('accents.bib')).origins)
    end)

    it('records the glob pattern a search path was expanded from', function()
      local sources = scan.resolve_bib_sources(bufnr, {
        search_paths = { 'tests/fixtures/*.bib' },
        root_markers = { '.git' },
      })
      assert.are.same({
        { kind = 'search_paths', detail = 'tests/fixtures/*.bib' },
      }, source_for(sources, helpers.fixture('refs.bib')).origins)
    end)

    it('records the local bibliography target', function()
      local sources = scan.resolve_bib_sources(bufnr, {
        root_markers = { '.git' },
        local_bib = { target = 'tests/fixtures/refs.bib' },
      })
      assert.are.same({
        { kind = 'local_bib', detail = 'tests/fixtures/refs.bib' },
      }, source_for(sources, helpers.fixture('refs.bib')).origins)
    end)

    it('keeps a path that does not exist', function()
      local sources = scan.resolve_bib_sources(bufnr, { files = { fixtures .. '/nope.bib' } })
      local source = source_for(sources, helpers.fixture('nope.bib'))
      assert.is_false(source.exists)
      assert.is_false(source.is_dir)
    end)

    it('keeps a directory, marked as one', function()
      local sources = scan.resolve_bib_sources(bufnr, { files = { fixtures .. '/project' } })
      local source = source_for(sources, helpers.fixture('project'))
      assert.is_true(source.exists)
      assert.is_true(source.is_dir)
    end)

    it('resolves the same paths resolve_bib_paths returns', function()
      local opts = {
        files = { fixtures .. '/refs.bib', fixtures .. '/nope.bib', fixtures .. '/project' },
        global_files = { fixtures .. '/accents.bib' },
      }
      local expected = {}
      for _, source in ipairs(scan.resolve_bib_sources(bufnr, opts)) do
        if source.exists and not source.is_dir then
          expected[#expected + 1] = source.path
        end
      end
      assert.are.same(expected, scan.resolve_bib_paths(bufnr, opts))
      assert.are.same({ helpers.fixture('refs.bib'), helpers.fixture('accents.bib') }, expected)
    end)
  end)

  it('accumulates an origin per report of the same path', function()
    local sources = scan.resolve_bib_sources(open_fixture('project/main.tex', 'tex'), {
      files = { fixtures .. '/project/bib/refs.bib' },
    })
    local source = source_for(sources, helpers.fixture('project/bib/refs.bib'))
    assert.are.same({
      { kind = 'buffer', detail = 'bib/refs.bib', hook = 'latex', line = 3 },
      { kind = 'files', detail = fixtures .. '/project/bib/refs.bib' },
    }, source.origins)
  end)
end)

describe('scan.global_set', function()
  it('normalizes the configured global files into a set', function()
    local set = scan.global_set({ global_files = helpers.fixture('refs.bib') })
    assert.is_true(scan.is_global_path(helpers.fixture('refs.bib'), set))
    assert.is_false(scan.is_global_path(helpers.fixture('accents.bib'), set))
  end)

  it('resolves a function-valued global_files option', function()
    local set = scan.global_set({
      global_files = function()
        return { helpers.fixture('refs.bib') }
      end,
    })
    assert.is_true(scan.is_global_path(helpers.fixture('refs.bib'), set))
  end)

  it('is empty when nothing is configured', function()
    assert.are.same({}, scan.global_set({}))
    assert.are.same({}, scan.global_set(nil))
    assert.is_false(scan.is_global_path(helpers.fixture('refs.bib'), scan.global_set(nil)))
  end)
end)
