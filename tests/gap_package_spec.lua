--- Tests for the GAP package bibliography discovery hook.

local assert = require('luassert')
local discovery = require('blink-cmp-bibtex.discovery')
local config = require('blink-cmp-bibtex.config')
local helpers = require('tests.helpers')

--- Build a discovery context for a file inside a package.
--- @param path string|nil Absolute path of the buffer's file
--- @param lines string[]|nil Buffer lines
--- @param filetype string|nil
--- @return BibtexDiscoveryContext
local function ctx(path, lines, filetype)
  return {
    bufnr = 0,
    filetype = filetype or 'gap',
    lines = lines or { '' },
    bufname = path,
    dir = path and vim.fs.dirname(path) or nil,
    root = path and vim.fs.dirname(path) or nil,
    opts = {},
  }
end

--- Lay out a minimal GAP package and return its root.
--- @param dir string The temporary directory
--- @param files table<string, string> Paths relative to the package root
--- @return string The package root
local function make_package(dir, files)
  local root = vim.fs.joinpath(vim.fs.normalize(dir), 'pkg')
  for rel, content in pairs(files) do
    helpers.write_file(vim.fs.joinpath(root, rel), content)
  end
  return root
end

--- Count the files opened while running a function.
--- @param fn function
--- @return number The number of io.open calls
local function count_reads(fn)
  local original = io.open
  local calls = 0
  --- @diagnostic disable-next-line: duplicate-set-field
  io.open = function(...) -- luacheck: ignore
    calls = calls + 1
    return original(...)
  end
  local ok, err = pcall(fn)
  io.open = original -- luacheck: ignore
  assert.is_true(ok, tostring(err))
  return calls
end

local package_info = 'SetPackageInfo( rec(\nPackageName := "LocalNR",\nVersion := "1.0",\n) );\n'

describe('discovery.gap_package', function()
  before_each(function()
    discovery.__test.reset()
  end)

  it('reads the databases the main XML declares', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Book Name="LocalNR">\n<Bibliography Databases="manual, gapdoc"/>\n</Book>\n',
        ['lib/foo.gd'] = '#! @Chapter Local\n',
      })
      assert.are.same({
        vim.fs.joinpath(root, 'doc/manual.bib'),
        vim.fs.joinpath(root, 'doc/gapdoc.bib'),
      }, discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
    end)
  end)

  it('falls back to the AutoDoc convention when no manual has been built', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['lib/foo.gd'] = '#! @Chapter Local\n',
      })
      assert.are.same(
        { vim.fs.joinpath(root, 'doc/LocalNR.bib') },
        discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      )
    end)
  end)

  it('prefers the bibliography makedoc.g names over the package name', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['makedoc.g'] = 'AutoDoc( rec( scaffold := rec( bib := "manual.bib" ) ) );\n',
        ['lib/foo.gd'] = '',
      })
      assert.are.same(
        { vim.fs.joinpath(root, 'doc/manual.bib') },
        discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      )
    end)
  end)

  it('skips a BibXMLext database named in makedoc.g', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['makedoc.g'] = 'AutoDoc( rec( scaffold := rec( bib := "refs.xml" ) ) );\n',
        ['lib/foo.gd'] = '',
      })
      assert.are.same(
        { vim.fs.joinpath(root, 'doc/LocalNR.bib') },
        discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      )
    end)
  end)

  it('honours the documentation directory makedoc.g names', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['makedoc.g'] = 'AutoDoc( rec( dir := "docs", scaffold := rec( ) ) );\n',
        ['docs/_main.xml'] = '<Bibliography Databases="manual"/>\n',
        ['lib/foo.gd'] = '',
      })
      assert.are.same(
        { vim.fs.joinpath(root, 'docs/manual.bib') },
        discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      )
    end)
  end)

  it('ignores a comment when reading a GAP file', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = '# PackageName := "Commented",\nPackageName := "LocalNR",\n',
        ['lib/foo.gd'] = '',
      })
      assert.are.same(
        { vim.fs.joinpath(root, 'doc/LocalNR.bib') },
        discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      )
    end)
  end)

  it('reads the main manual before another chapter file', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/chapter.xml'] = '<Bibliography Databases="chapter"/>\n',
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
        ['lib/foo.gd'] = '',
      })
      assert.are.same(
        { vim.fs.joinpath(root, 'doc/manual.bib') },
        discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      )
    end)
  end)

  it('skips an XML file larger than the cap', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n' .. string.rep('x', 200),
        ['lib/foo.gd'] = '',
      })
      local caps = discovery.__test.gap_size_caps
      local original = caps.xml
      caps.xml = 64
      local ok, result = pcall(discovery.gap_package, ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      caps.xml = original
      assert.is_true(ok, tostring(result))
      -- The manual was never read, so only the convention remains.
      assert.are.same({ vim.fs.joinpath(root, 'doc/LocalNR.bib') }, result)
    end)
  end)

  it('leaves a buffer that declares its own bibliography to the gapdoc hook', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
      })
      local context = ctx(vim.fs.joinpath(root, 'doc/_main.xml'), { '<Bibliography Databases="manual"/>' }, 'xml')
      assert.are.same({}, discovery.gap_package(context))
    end)
  end)

  it('finds nothing outside a GAP package', function()
    helpers.with_tmpdir(function(dir)
      local root = vim.fs.normalize(dir)
      helpers.write_file(vim.fs.joinpath(root, 'lib/foo.gd'), '')
      assert.are.same({}, discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
    end)
  end)

  it('finds nothing for a buffer without a file', function()
    assert.are.same({}, discovery.gap_package(ctx(nil)))
  end)

  it('reuses what it found until the package changes', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
        ['lib/foo.gd'] = '',
      })
      local context = ctx(vim.fs.joinpath(root, 'lib/foo.gd'))
      local expected = { vim.fs.joinpath(root, 'doc/manual.bib') }
      assert.is_true(count_reads(function()
        assert.are.same(expected, discovery.gap_package(context))
      end) > 0)
      assert.are.equal(
        0,
        count_reads(function()
          assert.are.same(expected, discovery.gap_package(context))
        end),
        'read the package again despite nothing having changed'
      )

      helpers.write_file(vim.fs.joinpath(root, 'doc/_main.xml'), '<Bibliography Databases="refs, extra"/>\n')
      assert.are.same({
        vim.fs.joinpath(root, 'doc/refs.bib'),
        vim.fs.joinpath(root, 'doc/extra.bib'),
      }, discovery.gap_package(context))
    end)
  end)

  it('notices a manual added to the documentation directory', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/intro.txt'] = 'notes\n',
        ['lib/foo.gd'] = '',
      })
      local context = ctx(vim.fs.joinpath(root, 'lib/foo.gd'))
      assert.are.same({ vim.fs.joinpath(root, 'doc/LocalNR.bib') }, discovery.gap_package(context))

      helpers.write_file(vim.fs.joinpath(root, 'doc/_main.xml'), '<Bibliography Databases="manual"/>\n')
      assert.are.same({ vim.fs.joinpath(root, 'doc/manual.bib') }, discovery.gap_package(context))
    end)
  end)
end)

describe('discovery.gap_package registration', function()
  before_each(function()
    discovery.__test.reset()
  end)

  it('inherits the shipped spec of the filetype it is registered under', function()
    local spec = assert(discovery.normalize('gap_package', true, 'gap'))
    assert.are.equal(discovery.gap_package, spec.find)
    assert.are.equal(45, spec.priority)
    assert.is_false(spec.extension)
  end)

  it('runs after the buffer hooks for the GAP filetypes', function()
    local defaults = config.defaults()
    for _, filetype in ipairs({ 'gap', 'xml', 'autodoc' }) do
      assert.are.same(
        { 'latex', 'yaml', 'typst', 'gapdoc', 'gap_package' },
        vim.tbl_map(function(spec)
          return spec.name
        end, discovery.chain(filetype, defaults)),
        'unexpected chain for ' .. filetype
      )
    end
  end)

  it('leaves the chain of the other filetypes alone', function()
    assert.are.same(
      { 'latex', 'yaml', 'typst', 'gapdoc' },
      vim.tbl_map(function(spec)
        return spec.name
      end, discovery.chain('markdown', config.defaults()))
    )
  end)
end)
