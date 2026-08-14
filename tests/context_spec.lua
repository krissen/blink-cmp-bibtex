--- Characterization tests for citation context extraction.
--- These assert the CURRENT behavior of the matchers, including quirks.

local assert = require('luassert')
local Source = require('blink-cmp-bibtex')
local config = require('blink-cmp-bibtex.config')
local helpers = require('tests.helpers')

local extract_context = Source.__test.extract_context

--- Run extract_context against a line with the default options.
--- @param filetype string
--- @param line string
--- @param col number|nil
--- @return table|nil
local function detect(filetype, line, col)
  return extract_context(helpers.ctx(line, col), config.defaults(), filetype)
end

describe('extract_context', function()
  describe('LaTeX citations', function()
    local cases = {
      { line = '\\cite{', prefix = '', command = 'cite' },
      { line = '\\cite{key', prefix = 'key', command = 'cite' },
      { line = '\\parencite[see][p. 42]{k', prefix = 'k', command = 'parencite' },
      { line = '\\cite*{k', prefix = 'k', command = 'cite*' },
      { line = '\\footcite{a,b', prefix = 'a,b', command = 'footcite' },
      { line = 'text before \\citep{a', prefix = 'a', command = 'citep' },
      { line = '\\autocite[p.~5]{x', prefix = 'x', command = 'autocite' },
    }

    for _, case in ipairs(cases) do
      it('matches ' .. case.line, function()
        local result = detect('tex', case.line)
        assert.are.same({
          prefix = case.prefix,
          command = case.command,
          trigger = 'latex',
        }, result)
      end)
    end

    it('ignores commands outside citation_commands', function()
      assert.is_nil(detect('tex', '\\unknowncmd{k'))
    end)

    it('returns nil once the closing brace is typed', function()
      assert.is_nil(detect('tex', '\\cite{key}'))
    end)

    it('respects the cursor column rather than the full line', function()
      local result = detect('tex', '\\cite{key} trailing text', 8)
      assert.are.same({ prefix = 'ke', command = 'cite', trigger = 'latex' }, result)
    end)
  end)

  describe('Pandoc citations in markdown', function()
    local cases = {
      { line = '[@k', prefix = 'k' },
      { line = 'see @k', prefix = 'k' },
      { line = '@k', prefix = 'k' },
    }

    for _, case in ipairs(cases) do
      it('matches ' .. case.line, function()
        local result = detect('markdown', case.line)
        assert.are.same({ prefix = case.prefix, trigger = 'pandoc' }, result)
      end)
    end

    it('keeps the whole bracket group as prefix for multi-key citations', function()
      -- current behavior (quirk): the raw prefix still contains the earlier
      -- keys; sanitize_prefix is what narrows it down to the last one.
      assert.are.same({ prefix = 'a; @b', trigger = 'pandoc' }, detect('markdown', '[@a; @b'))
    end)

    it('ignores an email-like address', function()
      -- Deliberate change: the Typst matcher used to run as a last-chance
      -- fallback in every filetype and answered here, so typing an address
      -- produced citation completions. It is now scoped to typst buffers.
      assert.is_nil(detect('markdown', 'email@k'))
    end)

    it('returns nil for a completed bracket group', function()
      assert.is_nil(detect('markdown', 'Text [@a; @b] done'))
    end)

    it('returns nil for an empty line', function()
      assert.is_nil(detect('markdown', ''))
    end)
  end)

  describe('Typst citations', function()
    local cases = {
      { line = '@k', prefix = 'k' },
      { line = '#cite(<k', prefix = 'k' },
      { line = 'word@k', prefix = 'k' },
      { line = '[@k', prefix = 'k' },
      { line = 'see @k', prefix = 'k' },
    }

    for _, case in ipairs(cases) do
      it('matches ' .. case.line, function()
        local result = detect('typst', case.line)
        assert.are.same({ prefix = case.prefix, trigger = 'typst' }, result)
      end)
    end

    it('does not match #cite(<key outside typst buffers', function()
      -- Deliberate change: Typst syntax is only recognized in typst buffers
      -- now that the matcher is no longer a fallback for every filetype.
      assert.is_nil(detect('markdown', '#cite(<k'))
    end)
  end)

  describe('matcher ordering', function()
    for _, filetype in ipairs({ 'tex', 'markdown', 'typst', 'rmd' }) do
      it('prefers the LaTeX matcher in filetype ' .. filetype, function()
        local result = detect(filetype, '\\cite{k')
        assert.are.same({ prefix = 'k', command = 'cite', trigger = 'latex' }, result)
      end)
    end

    it('prefers Typst over Pandoc in typst buffers', function()
      assert.are.equal('typst', detect('typst', '[@k').trigger)
    end)

    it('prefers Pandoc over Typst outside typst buffers', function()
      assert.are.equal('pandoc', detect('markdown', '[@k').trigger)
      -- current behavior (quirk): Pandoc syntax is also matched in LaTeX files.
      assert.are.equal('pandoc', detect('tex', '@k').trigger)
    end)
  end)
end)

describe('sanitize_prefix', function()
  local sanitize_prefix = Source.__test.sanitize_prefix

  local cases = {
    { input = '', expected = '' },
    { input = 'a,b', expected = 'b' },
    { input = 'a; @b', expected = 'b' },
    { input = '@k', expected = 'k' },
    { input = '  k  ', expected = 'k' },
    { input = 'a,', expected = '' },
    { input = 'x; y; z', expected = 'z' },
  }

  for _, case in ipairs(cases) do
    it(string.format('maps %q to %q', case.input, case.expected), function()
      assert.are.equal(case.expected, sanitize_prefix(case.input))
    end)
  end

  it('returns an empty string for nil', function()
    assert.are.equal('', sanitize_prefix(nil))
  end)
end)
