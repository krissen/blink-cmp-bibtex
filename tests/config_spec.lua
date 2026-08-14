--- Characterization tests for configuration merging.

local assert = require('luassert')
local config = require('blink-cmp-bibtex.config')

describe('config', function()
  after_each(function()
    -- Restore the module-level options for the following tests.
    config.setup(nil)
  end)

  it('exposes defaults', function()
    local defaults = config.defaults()
    assert.are.same({ 'tex', 'plaintex', 'markdown', 'rmd', 'typst' }, defaults.filetypes)
    assert.are.equal('apa', defaults.preview_style)
    assert.are.equal(4000, defaults.max_entries)
    assert.is_false(defaults.local_bib.enabled)
  end)

  it('merges user options over the defaults', function()
    local opts = config.setup({ preview_style = 'ieee' })
    assert.are.equal('ieee', opts.preview_style)
    assert.are.equal(4000, opts.max_entries)
  end)

  it('is non-cumulative across setup calls', function()
    config.setup({ preview_style = 'ieee' })
    local second = config.setup({ max_entries = 10 })
    assert.are.equal('apa', second.preview_style)
    assert.are.equal(10, second.max_entries)
  end)

  it('keeps sibling keys when overriding a nested local_bib field', function()
    local opts = config.setup({ local_bib = { enabled = true } })
    assert.is_true(opts.local_bib.enabled)
    assert.are.same({ 'local.bib', 'references.bib' }, opts.local_bib.patterns)
    assert.is_true(opts.local_bib.notify_on_add)
    assert.is_true(opts.local_bib.duplicate_check)
  end)

  it('does not mutate the defaults table', function()
    config.setup({ preview_style = 'ieee', local_bib = { enabled = true } })
    local defaults = config.defaults()
    assert.are.equal('apa', defaults.preview_style)
    assert.is_false(defaults.local_bib.enabled)
  end)

  it('returns the active options from get', function()
    config.setup({ preview_style = 'ieee' })
    assert.are.equal('ieee', config.get().preview_style)
  end)

  it('extend layers on top of the active options without mutating them', function()
    config.setup({ preview_style = 'ieee' })
    local extended = config.extend({ max_entries = 5 })
    assert.are.equal('ieee', extended.preview_style)
    assert.are.equal(5, extended.max_entries)
    assert.are.equal(4000, config.get().max_entries)
  end)

  it('extend with nil returns the active options unchanged', function()
    config.setup({ preview_style = 'ieee' })
    assert.are.equal('ieee', config.extend(nil).preview_style)
  end)

  it('replaces list options instead of merging them by index', function()
    -- A user who narrows citation_commands must not inherit the default tail.
    local opts = config.setup({ citation_commands = { 'cite', 'textcite' } })
    assert.are.same({ 'cite', 'textcite' }, opts.citation_commands)
    assert.are.same({ 'tex', 'plaintex', 'markdown', 'rmd', 'typst' }, config.defaults().filetypes)
  end)

  it('replaces a list with an empty one when asked to', function()
    assert.are.same({}, config.setup({ root_markers = {} }).root_markers)
  end)

  it('keeps nested map defaults when the override is an empty table', function()
    local opts = config.setup({ local_bib = {} })
    assert.are.same({ 'local.bib', 'references.bib' }, opts.local_bib.patterns)
  end)

  it('merges a user matcher filetype without clobbering the shared entries', function()
    local opts = config.setup({ matchers = { gap = { gapdoc = { priority = 5 } } } })
    assert.are.equal(10, opts.matchers['*'].latex.priority)
    assert.are.equal(20, opts.matchers.typst.typst.priority)
    assert.are.equal(5, opts.matchers.gap.gapdoc.priority)
  end)

  it('keeps a disabled matcher across setup and extend', function()
    config.setup({ matchers = { markdown = { pandoc = false } } })
    local extended = config.extend({ preview_style = 'ieee' })
    assert.is_false(extended.matchers.markdown.pandoc)
  end)

  it('leaves the matcher chains at their defaults when nothing is configured', function()
    local matchers = require('blink-cmp-bibtex.matchers')
    local opts = config.setup({ preview_style = 'ieee' })
    for _, filetype in ipairs({ 'tex', 'markdown', 'typst', 'gap' }) do
      assert.are.same(matchers.chain(filetype, config.defaults()), matchers.chain(filetype, opts))
    end
  end)

  it('keeps discovery = false through setup, unlike an empty table', function()
    -- An empty map merges into the shipped hooks and therefore cannot express
    -- "discover nothing"; false replaces the table outright.
    assert.is_false(config.setup({ discovery = false }).discovery)
    assert.is_not_nil(config.setup({ discovery = {} }).discovery['*'])
  end)

  it('merges a user discovery hook without clobbering the shipped ones', function()
    local opts = config.setup({ discovery = { rst = { mine = false } } })
    assert.are.equal(10, opts.discovery['*'].latex.priority)
    assert.is_false(opts.discovery.rst.mine)
  end)

  describe('non-table option values', function()
    --- Run a function with vim.notify silenced.
    --- @param fn function
    --- @return any
    local function quietly(fn)
      local original = vim.notify
      --- @diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(_msg, _level, _opts) end
      local ok, result = pcall(fn)
      --- @diagnostic disable-next-line: duplicate-set-field
      vim.notify = original
      if not ok then
        error(result, 0)
      end
      return result
    end

    -- Every one of these used to crash a completion round, the scanner or the
    -- health check rather than being reported and ignored.
    local scalars = { ['true'] = true, ['false'] = false, ['a string'] = 'x', ['a number'] = 42 }
    local table_options = { 'matchers', 'discovery', 'local_bib', 'filetypes', 'citation_commands', 'root_markers' }

    for _, name in ipairs(table_options) do
      for label, value in pairs(scalars) do
        it(string.format('replaces %s = %s with something usable', name, label), function()
          local opts = quietly(function()
            return config.setup({ [name] = value })
          end)
          local resolved = opts[name]
          if (name == 'matchers' or name == 'discovery') and type(resolved) == 'boolean' then
            -- The registries keep false, which disables them, and it is a
            -- boolean rather than a table by design.
            assert.is_false(resolved)
          else
            assert.are.equal('table', type(resolved), name .. ' = ' .. label)
          end
        end)
      end
    end

    it('reads registry = true as the shipped entries', function()
      assert.are.same(config.defaults().discovery, config.setup({ discovery = true }).discovery)
      assert.are.same(config.defaults().matchers, config.setup({ matchers = true }).matchers)
    end)

    it('keeps registry = false, which disables the chain', function()
      assert.is_false(config.setup({ discovery = false }).discovery)
      assert.is_false(config.setup({ matchers = false }).matchers)
    end)

    it('keeps a string or function path option, which are both supported', function()
      assert.are.equal('refs.bib', config.setup({ files = 'refs.bib' }).files)
      local fn = function() end
      assert.are.equal(fn, config.setup({ global_files = fn }).global_files)
    end)

    it('replaces a path option that is neither a list, a string nor a function', function()
      local opts = quietly(function()
        return config.setup({ files = 42 })
      end)
      assert.are.same({}, opts.files)
    end)

    it('warns once about an unusable value', function()
      local messages = {}
      local original = vim.notify
      --- @diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(msg, _level, _opts)
        messages[#messages + 1] = msg
      end
      local ok = pcall(function()
        require('blink-cmp-bibtex.registry').reset()
        config.setup({ filetypes = 42 })
        config.setup({ filetypes = 42 })
      end)
      --- @diagnostic disable-next-line: duplicate-set-field
      vim.notify = original
      assert.is_true(ok)
      assert.are.equal(1, #messages)
      assert.is_truthy(messages[1]:find("option 'filetypes' is number", 1, true))
    end)
  end)

  it('setup with nil resets to the defaults', function()
    config.setup({ preview_style = 'ieee' })
    local reset = config.setup(nil)
    assert.are.equal('apa', reset.preview_style)
    -- current behavior (quirk): the defaults table is adopted by identity
    -- rather than copied, so mutating the active options would edit defaults.
    assert.is_true(rawequal(config.defaults(), reset))
  end)
end)
