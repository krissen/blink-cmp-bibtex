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

  it('setup with nil resets to the defaults', function()
    config.setup({ preview_style = 'ieee' })
    local reset = config.setup(nil)
    assert.are.equal('apa', reset.preview_style)
    -- current behavior (quirk): the defaults table is adopted by identity
    -- rather than copied, so mutating the active options would edit defaults.
    assert.is_true(rawequal(config.defaults(), reset))
  end)
end)
