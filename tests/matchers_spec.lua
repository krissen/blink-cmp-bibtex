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
    -- Plain functions inherit nothing, so all three share the default priority.
    local opts = {
      matchers = {
        ['*'] = { zulu = function() end, alpha = function() end, mike = function() end },
      },
    }
    assert.are.same({ 'alpha', 'mike', 'zulu' }, names(matchers.chain('tex', opts)))
  end)

  it('keeps the shipped priority when a built-in is re-enabled with true', function()
    -- Regression: the shorthand forms used to land at the default priority, so
    -- `typst = true` silently moved typst from 20 to behind pandoc's 30.
    local opts = { matchers = { ['*'] = { pandoc = true }, typst = { typst = true } } }
    assert.are.same({ 'typst', 'pandoc' }, names(matchers.chain('typst', opts)))
    local chain = matchers.chain('typst', opts)
    assert.are.equal(20, chain[1].priority)
    assert.are.equal(30, chain[2].priority)
  end)

  it('keeps the shipped trigger characters when gapdoc is re-enabled with true', function()
    local opts = { matchers = { gap = { gapdoc = true } } }
    local chain = matchers.chain('gap', opts)
    assert.are.equal(5, chain[1].priority)
    assert.are.same({ '"' }, chain[1].trigger_characters)
  end)

  it('inherits the shared priority for a built-in named by a string', function()
    local opts = { matchers = { ['*'] = { citations = 'pandoc' } } }
    assert.are.equal(30, matchers.chain('markdown', opts)[1].priority)
  end)

  it('lets an explicit priority win over the shipped one', function()
    local opts = { matchers = { typst = { typst = { priority = 99 } } } }
    assert.are.equal(99, matchers.chain('typst', opts)[1].priority)
  end)

  it('falls back to the default priority for a built-in the filetype does not ship', function()
    -- typst is shipped only under the typst filetype, so enabling it elsewhere
    -- has no shipped priority to inherit.
    local opts = { matchers = { markdown = { typst = true } } }
    assert.are.equal(50, matchers.chain('markdown', opts)[1].priority)
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

  it('keeps a broken override in one filetype from disabling the built-in elsewhere', function()
    local opts = {
      matchers = {
        ['*'] = { pandoc = { priority = 30 } },
        markdown = {
          pandoc = {
            priority = 30,
            match = function()
              error('boom')
            end,
          },
        },
      },
    }
    with_notify_capture(function()
      assert.is_nil(matchers.detect('[@k', opts, { filetype = 'markdown' }))
      local result, spec = matchers.detect('[@k', opts, { filetype = 'rmd' })
      assert.are.equal('k', assert(result).prefix)
      assert.are.equal('pandoc', assert(spec).name)
    end)
  end)

  it('treats a truthy non-table result as a matcher failure', function()
    local opts = {
      matchers = {
        ['*'] = {
          bogus = {
            priority = 1,
            match = function()
              return true
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
      local result = assert(matchers.detect('x', opts, { filetype = 'tex' }))
      assert.are.equal('ok', result.prefix)
      assert.are.equal(1, #messages)
      assert.is_truthy(messages[1]:find('instead of a table', 1, true))
    end)
  end)

  it('treats a result without a string prefix as a matcher failure', function()
    local opts = {
      matchers = {
        ['*'] = {
          bogus = {
            priority = 1,
            match = function()
              return { trigger = 'bogus' }
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
      local result = assert(matchers.detect('x', opts, { filetype = 'tex' }))
      assert.are.equal('ok', result.prefix)
      assert.are.equal(1, #messages)
      assert.is_truthy(messages[1]:find('prefix is nil', 1, true))
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
