--- Tests for matcher registration, dispatch and the GAPDoc matcher.

local assert = require('luassert')
local matchers = require('blink-cmp-bibtex.matchers')
local config = require('blink-cmp-bibtex.config')

--- Collect the names of a chain, in order.
--- @param chain table[]
--- @return string[]
local function names(chain)
  return vim.tbl_map(function(spec)
    return spec.name
  end, chain)
end

--- Run a function with vim.notify replaced by a recorder.
--- @param fn function Receives the list that collects the messages
--- @return any The value returned by fn
local function with_notify_capture(fn)
  local messages = {}
  local original = vim.notify
  vim.notify = function(msg)
    messages[#messages + 1] = msg
  end
  local ok, result = pcall(fn, messages)
  vim.notify = original
  if not ok then
    error(result, 0)
  end
  return result
end

describe('matchers.normalize', function()
  before_each(function()
    matchers.__test.reset()
  end)

  it('wraps a function into a spec with the default priority', function()
    local fn = function() end
    local spec = assert(matchers.normalize('custom', fn))
    assert.are.equal(fn, spec.match)
    assert.are.equal('custom', spec.name)
    assert.are.equal(50, spec.priority)
  end)

  it('keeps the match function and options of a spec table', function()
    local fn = function() end
    local spec = assert(matchers.normalize('custom', { match = fn, priority = 3, sanitize = false }))
    assert.are.equal(fn, spec.match)
    assert.are.equal(3, spec.priority)
    assert.is_false(spec.sanitize)
  end)

  it('falls back to the built-in matcher named by the key', function()
    local spec = assert(matchers.normalize('latex', { priority = 10 }))
    assert.are.equal(matchers.latex, spec.match)
    assert.are.equal(10, spec.priority)
  end)

  it('resolves a string to the named built-in matcher', function()
    local spec = assert(matchers.normalize('citations', 'pandoc'))
    assert.are.equal(matchers.pandoc, spec.match)
  end)

  it('resolves true to the built-in matcher named by the key', function()
    assert.are.equal(matchers.typst, assert(matchers.normalize('typst', true)).match)
  end)

  it('treats false and nil as disabled', function()
    assert.is_nil(matchers.normalize('latex', false))
    assert.is_nil(matchers.normalize('latex', nil))
  end)

  it('skips invalid values with a warning instead of throwing', function()
    with_notify_capture(function(messages)
      assert.is_nil(matchers.normalize('nosuch', true))
      assert.is_nil(matchers.normalize('alias', 'nosuch'))
      assert.is_nil(matchers.normalize('table', { priority = 1 }))
      assert.is_nil(matchers.normalize('number', 42))
      assert.are.equal(4, #messages)
    end)
  end)

  it('warns only once per matcher name', function()
    with_notify_capture(function(messages)
      matchers.normalize('nosuch', true)
      matchers.normalize('nosuch', true)
      assert.are.equal(1, #messages)
    end)
  end)
end)

describe('matchers.chain', function()
  it('uses the shared entries for an unknown filetype', function()
    local opts = { matchers = { ['*'] = { latex = { priority = 10 }, pandoc = { priority = 30 } } } }
    assert.are.same({ 'latex', 'pandoc' }, names(matchers.chain('cobol', opts)))
  end)

  it('lets a filetype entry override the priority of a shared entry', function()
    local opts = {
      matchers = {
        ['*'] = { latex = { priority = 10 }, pandoc = { priority = 30 } },
        markdown = { pandoc = { priority = 1 } },
      },
    }
    assert.are.same({ 'pandoc', 'latex' }, names(matchers.chain('markdown', opts)))
  end)

  it('lets a filetype entry disable a shared entry with false', function()
    local opts = {
      matchers = {
        ['*'] = { latex = { priority = 10 }, pandoc = { priority = 30 } },
        markdown = { pandoc = false },
      },
    }
    assert.are.same({ 'latex' }, names(matchers.chain('markdown', opts)))
  end)

  it('runs a user matcher with priority 1 before the built-ins', function()
    local opts = {
      matchers = {
        ['*'] = { latex = { priority = 10 }, mine = { match = function() end, priority = 1 } },
      },
    }
    assert.are.same({ 'mine', 'latex' }, names(matchers.chain('tex', opts)))
  end)

  it('breaks ties on the matcher name', function()
    local opts = {
      matchers = { ['*'] = { zulu = 'latex', alpha = 'pandoc', mike = 'typst' } },
    }
    assert.are.same({ 'alpha', 'mike', 'zulu' }, names(matchers.chain('tex', opts)))
  end)

  it('returns an empty chain when nothing is configured', function()
    assert.are.same({}, matchers.chain('tex', {}))
  end)
end)

describe('matchers.detect', function()
  before_each(function()
    matchers.__test.reset()
  end)

  it('returns the matching spec alongside the result', function()
    local opts = config.defaults()
    local result, spec = matchers.detect('\\cite{k', opts, { filetype = 'tex' })
    assert.are.equal('k', assert(result).prefix)
    assert.are.equal('latex', assert(spec).name)
  end)

  it('stops at the first matcher that returns a result', function()
    local calls = {}
    local opts = {
      matchers = {
        ['*'] = {
          first = {
            priority = 1,
            match = function()
              calls[#calls + 1] = 'first'
              return { prefix = 'a' }
            end,
          },
          second = {
            priority = 2,
            match = function()
              calls[#calls + 1] = 'second'
              return { prefix = 'b' }
            end,
          },
        },
      },
    }
    local result = assert(matchers.detect('anything', opts, { filetype = 'tex' }))
    assert.are.equal('a', result.prefix)
    assert.are.same({ 'first' }, calls)
  end)

  it('skips a throwing matcher, warns once and keeps the chain running', function()
    local opts = {
      matchers = {
        ['*'] = {
          broken = {
            priority = 1,
            match = function()
              error('boom')
            end,
          },
          good = {
            priority = 2,
            match = function()
              return { prefix = 'ok' }
            end,
          },
        },
      },
    }
    with_notify_capture(function(messages)
      local first = assert(matchers.detect('x', opts, { filetype = 'tex' }))
      local second = assert(matchers.detect('x', opts, { filetype = 'tex' }))
      assert.are.equal('ok', first.prefix)
      assert.are.equal('ok', second.prefix)
      assert.are.equal(1, #messages)
    end)
  end)

  it('returns nil when no matcher matches', function()
    assert.is_nil(matchers.detect('plain prose', config.defaults(), { filetype = 'tex' }))
  end)
end)

describe('matchers.gapdoc', function()
  local cases = {
    { line = '<Cite Key="', prefix = '' },
    { line = '<Cite Key="Ha', prefix = 'Ha' },
    { line = '<Cite Key="a,b', prefix = 'a,b' },
    { line = "<Cite Key='Ha", prefix = 'Ha' },
    { line = '<Cite Where="1.2" Key="Ha', prefix = 'Ha' },
    { line = 'text <Cite  Key = "Ha', prefix = 'Ha' },
    { line = 'As shown in <Cite Key="proj', prefix = 'proj' },
  }

  for _, case in ipairs(cases) do
    it(string.format('matches %q', case.line), function()
      local result = matchers.gapdoc(case.line)
      assert.are.same({ prefix = case.prefix, trigger = 'gapdoc', sanitize = false }, result)
    end)
  end

  local misses = {
    '<Cite Key="key"/>',
    '<Citation Key="Ha',
    '<Cite Name="Ha',
    'Key="Ha',
  }

  for _, line in ipairs(misses) do
    it(string.format('does not match %q', line), function()
      assert.is_nil(matchers.gapdoc(line))
    end)
  end

  it('is reachable through the default gap chain', function()
    local result, spec = matchers.detect('<Cite Key="pro', config.defaults(), { filetype = 'gap' })
    assert.are.equal('pro', assert(result).prefix)
    assert.are.equal('gapdoc', assert(spec).name)
  end)
end)

describe('matchers.trigger_characters', function()
  it('is empty for the built-in citation filetypes', function()
    -- Regression guard: latex, pandoc and typst must not open the menu on
    -- characters of their own, which would change long-standing behavior.
    for _, filetype in ipairs({ 'tex', 'markdown', 'typst', 'rmd' }) do
      assert.are.same({}, matchers.trigger_characters(filetype, config.defaults()))
    end
  end)

  it('collects the quote used by the GAPDoc matcher', function()
    assert.are.same({ '"' }, matchers.trigger_characters('gap', config.defaults()))
  end)

  it('deduplicates characters declared by several matchers', function()
    local opts = {
      matchers = {
        ['*'] = {
          a = { match = function() end, trigger_characters = { '"', '<' } },
          b = { match = function() end, trigger_characters = { '"' } },
        },
      },
    }
    assert.are.same({ '"', '<' }, matchers.trigger_characters('tex', opts))
  end)
end)
