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

  it('setup with nil resets to the defaults', function()
    config.setup({ preview_style = 'ieee' })
    local reset = config.setup(nil)
    assert.are.equal('apa', reset.preview_style)
    -- current behavior (quirk): the defaults table is adopted by identity
    -- rather than copied, so mutating the active options would edit defaults.
    assert.is_true(rawequal(config.defaults(), reset))
  end)
end)
