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

--- Project the names of what the hook reported.
--- @param results table[] The records discovery.gap_package returned
--- @return string[]
local function names(results)
  return vim.tbl_map(function(entry)
    return entry.name
  end, results)
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

--- Run a function with vim.fs.dir returning a fixed listing of files.
--- @param entries string[] The names the directory reports, in order
--- @param fn function
--- @return any The value returned by fn
local function with_dir_listing(entries, fn)
  local original = vim.fs.dir
  -- The full signature matters: the language server merges every assignment to
  -- vim.fs.dir across the workspace, so a stub taking no parameters would
  -- redefine the function project-wide and flag every real call.
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.fs.dir = function(_path, _opts) -- luacheck: ignore
    local index = 0
    return function()
      index = index + 1
      if entries[index] then
        return entries[index], 'file'
      end
    end
  end
  local ok, result = pcall(fn)
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.fs.dir = original
  if not ok then
    error(result, 0)
  end
  return result
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
      }, names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))))
    end)
  end)

  it('reports the manual that declared a database, and nothing for the convention', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
        ['lib/foo.gd'] = '',
      })
      assert.are.same({
        { name = vim.fs.joinpath(root, 'doc/manual.bib'), file = vim.fs.joinpath(root, 'doc/_main.xml') },
      }, discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
    end)
  end)

  it('reports no declaring file for a database derived from the AutoDoc convention', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['lib/foo.gd'] = '',
      })
      assert.are.same(
        { { name = vim.fs.joinpath(root, 'doc/LocalNR.bib') } },
        discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      )
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
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
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
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
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
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
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
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
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
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
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
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
      )
    end)
  end)

  it('reads the main manual even when the chapters outnumber the cap', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['lib/foo.gd'] = '',
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
      })
      local listing = {}
      for index = 1, 6 do
        local name = string.format('chapter%d.xml', index)
        listing[#listing + 1] = name
        helpers.write_file(vim.fs.joinpath(root, 'doc/' .. name), '<Chapter/>\n')
      end
      -- The order a directory is read in is the file system's business, so it
      -- is fixed here: the manual comes last, and a cap applied to the walk
      -- rather than to the ranking would drop it.
      listing[#listing + 1] = '_main.xml'
      local limits = discovery.__test.gap_limits
      local original = limits.max_xml_files
      limits.max_xml_files = 2
      local ok, result = pcall(with_dir_listing, listing, function()
        return discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))
      end)
      limits.max_xml_files = original
      assert.is_true(ok, tostring(result))
      assert.are.same({ vim.fs.joinpath(root, 'doc/manual.bib') }, names(result))
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
      assert.are.same({ vim.fs.joinpath(root, 'doc/LocalNR.bib') }, names(result))
    end)
  end)

  it('leaves a buffer that declares its own bibliography to the gapdoc hook', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
      })
      local context = ctx(vim.fs.joinpath(root, 'doc/_main.xml'), { '<Bibliography Databases="manual"/>' }, 'xml')
      assert.are.same({}, names(discovery.gap_package(context)))
    end)
  end)

  it('still reads the package when the declaration is commented out', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
      })
      -- The gapdoc hook strips comments before reading, so it reports nothing
      -- here; deferring to it on the bare marker would find nothing at all.
      local context =
        ctx(vim.fs.joinpath(root, 'doc/chapter.xml'), { '<!-- <Bibliography Databases="old"/> -->' }, 'xml')
      assert.are.same({ vim.fs.joinpath(root, 'doc/manual.bib') }, names(discovery.gap_package(context)))
    end)
  end)

  it('still reads the package when the declaration sits in a CDATA section', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
      })
      local context =
        ctx(vim.fs.joinpath(root, 'doc/chapter.xml'), { '<![CDATA[ <Bibliography Databases="old"/> ]]>' }, 'xml')
      assert.are.same({ vim.fs.joinpath(root, 'doc/manual.bib') }, names(discovery.gap_package(context)))
    end)
  end)

  it('still reads the package when the declaration names no database', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
      })
      local context = ctx(vim.fs.joinpath(root, 'doc/chapter.xml'), { '<Bibliography Databases=""/>' }, 'xml')
      assert.are.same({ vim.fs.joinpath(root, 'doc/manual.bib') }, names(discovery.gap_package(context)))
    end)
  end)

  it('finds nothing outside a GAP package', function()
    helpers.with_tmpdir(function(dir)
      local root = vim.fs.normalize(dir)
      helpers.write_file(vim.fs.joinpath(root, 'lib/foo.gd'), '')
      assert.are.same({}, names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))))
    end)
  end)

  it('finds nothing for a buffer without a file', function()
    assert.are.same({}, names(discovery.gap_package(ctx(nil))))
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
        assert.are.same(expected, names(discovery.gap_package(context)))
      end) > 0)
      assert.are.equal(
        0,
        count_reads(function()
          assert.are.same(expected, names(discovery.gap_package(context)))
        end),
        'read the package again despite nothing having changed'
      )

      helpers.write_file(vim.fs.joinpath(root, 'doc/_main.xml'), '<Bibliography Databases="refs, extra"/>\n')
      assert.are.same({
        vim.fs.joinpath(root, 'doc/refs.bib'),
        vim.fs.joinpath(root, 'doc/extra.bib'),
      }, names(discovery.gap_package(context)))
    end)
  end)

  it('shares what it found between the buffers of one package', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
        ['lib/foo.gd'] = '',
        ['lib/bar.gd'] = '',
      })
      local expected = { vim.fs.joinpath(root, 'doc/manual.bib') }
      assert.is_true(count_reads(function()
        assert.are.same(expected, names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd')))))
      end) > 0)
      -- A second buffer of the same package reads the same files, so it must
      -- not send the hook back to the file system.
      assert.are.equal(
        0,
        count_reads(function()
          assert.are.same(expected, names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/bar.gd')))))
        end),
        'read the package again for another buffer of the same package'
      )
    end)
  end)

  it('rereads the package for a buffer that is one of its manuals', function()
    helpers.with_tmpdir(function(dir)
      local root = make_package(dir, {
        ['PackageInfo.g'] = package_info,
        ['doc/_main.xml'] = '<Bibliography Databases="manual"/>\n',
        ['lib/foo.gd'] = '',
      })
      assert.are.same(
        { vim.fs.joinpath(root, 'doc/manual.bib') },
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'lib/foo.gd'))))
      )
      -- Editing the manual itself skips it on disk, so the entry cached for
      -- the source file above cannot be reused.
      assert.are.same(
        { vim.fs.joinpath(root, 'doc/LocalNR.bib') },
        names(discovery.gap_package(ctx(vim.fs.joinpath(root, 'doc/_main.xml'), { '<Book/>' }, 'xml')))
      )
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
      assert.are.same({ vim.fs.joinpath(root, 'doc/LocalNR.bib') }, names(discovery.gap_package(context)))

      helpers.write_file(vim.fs.joinpath(root, 'doc/_main.xml'), '<Bibliography Databases="manual"/>\n')
      assert.are.same({ vim.fs.joinpath(root, 'doc/manual.bib') }, names(discovery.gap_package(context)))
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
