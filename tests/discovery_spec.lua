--- Tests for discovery hook registration and dispatch.

local assert = require('luassert')
local discovery = require('blink-cmp-bibtex.discovery')
local config = require('blink-cmp-bibtex.config')
local helpers = require('tests.helpers')

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
  -- The full signature matters: the language server merges every assignment to
  -- vim.notify across the workspace, so a stub taking one parameter would
  -- redefine the function project-wide and flag every real three-argument call.
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, _level, _opts)
    messages[#messages + 1] = msg
  end
  local ok, result = pcall(fn, messages)
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.notify = original
  if not ok then
    error(result, 0)
  end
  return result
end

--- Build a discovery context.
--- @param opts table|nil Configuration options
--- @param lines string[]|nil Buffer lines
--- @param filetype string|nil
--- @return BibtexDiscoveryContext
local function ctx(opts, lines, filetype)
  return {
    bufnr = 0,
    filetype = filetype or 'markdown',
    lines = lines or {},
    bufname = '/tmp/doc.md',
    dir = '/tmp',
    opts = opts or {},
  }
end

describe('discovery.normalize', function()
  before_each(function()
    discovery.__test.reset()
  end)

  it('wraps a function into a spec with the default priority', function()
    local fn = function() end
    local spec = assert(discovery.normalize('custom', fn))
    assert.are.equal(fn, spec.find)
    assert.are.equal('custom', spec.name)
    assert.are.equal(50, spec.priority)
  end)

  it('keeps the find function and options of a spec table', function()
    local fn = function() end
    local spec = assert(discovery.normalize('custom', { find = fn, priority = 3, extension = false }))
    assert.are.equal(fn, spec.find)
    assert.are.equal(3, spec.priority)
    assert.is_false(spec.extension)
  end)

  it('falls back to the built-in hook named by the key', function()
    local spec = assert(discovery.normalize('yaml', { priority = 20 }))
    assert.are.equal(discovery.yaml, spec.find)
    assert.are.equal(20, spec.priority)
  end)

  it('resolves a string to the named built-in hook', function()
    assert.are.equal(discovery.latex, assert(discovery.normalize('commands', 'latex')).find)
  end)

  it('resolves true to the built-in hook named by the key', function()
    assert.are.equal(discovery.typst, assert(discovery.normalize('typst', true)).find)
  end)

  it('inherits the shipped extension flag when a hook is re-enabled with true', function()
    -- GAPDoc appends its own extension, and that must survive re-enabling it.
    local spec = assert(discovery.normalize('gapdoc', true))
    assert.is_false(spec.extension)
    assert.are.equal(40, spec.priority)
  end)

  it('treats false and nil as disabled', function()
    assert.is_nil(discovery.normalize('latex', false))
    assert.is_nil(discovery.normalize('latex', nil))
  end)

  it('skips invalid values with a warning instead of throwing', function()
    with_notify_capture(function(messages)
      assert.is_nil(discovery.normalize('nosuch', true))
      assert.is_nil(discovery.normalize('alias', 'nosuch'))
      assert.is_nil(discovery.normalize('table', { priority = 1 }))
      assert.is_nil(discovery.normalize('number', 42))
      assert.are.equal(4, #messages)
    end)
  end)

  it('skips a spec whose optional fields are malformed', function()
    local malformed = {
      { spec = { priority = 'high' }, reason = 'priority is string' },
      { spec = { extension = 'yes' }, reason = 'extension is string' },
    }
    for _, case in ipairs(malformed) do
      discovery.__test.reset()
      with_notify_capture(function(messages)
        case.spec.find = function() end
        assert.is_nil(discovery.normalize('custom', case.spec))
        assert.are.equal(1, #messages)
        assert.is_truthy(messages[1]:find(case.reason, 1, true), messages[1])
      end)
    end
  end)
end)

describe('discovery.chain', function()
  before_each(function()
    discovery.__test.reset()
  end)

  it('runs the shipped hooks in their documented order', function()
    assert.are.same({ 'latex', 'yaml', 'typst', 'gapdoc' }, names(discovery.chain('markdown', config.defaults())))
  end)

  it('falls back to the shipped hooks when no discovery is configured', function()
    -- find_bib_files_from_buffer is public and is called without options.
    assert.are.same(names(discovery.chain('markdown', config.defaults())), names(discovery.chain('markdown', {})))
    assert.are.same(names(discovery.chain('markdown', config.defaults())), names(discovery.chain('markdown', nil)))
  end)

  it('discovers nothing when discovery is turned off', function()
    assert.are.same({}, discovery.chain('markdown', { discovery = false }))
    -- An empty table says the same thing, but only survives when the options
    -- are passed straight through rather than merged by setup().
    assert.are.same({}, discovery.chain('markdown', { discovery = {} }))
  end)

  it('lets a filetype entry override the priority of a shared entry', function()
    local opts = {
      discovery = {
        ['*'] = { latex = { priority = 10 }, yaml = { priority = 20 } },
        markdown = { yaml = { priority = 1 } },
      },
    }
    assert.are.same({ 'yaml', 'latex' }, names(discovery.chain('markdown', opts)))
    assert.are.same({ 'latex', 'yaml' }, names(discovery.chain('tex', opts)))
  end)

  it('lets a filetype entry disable a shared entry with false', function()
    local opts = {
      discovery = {
        ['*'] = { latex = { priority = 10 }, yaml = { priority = 20 } },
        markdown = { yaml = false },
      },
    }
    assert.are.same({ 'latex' }, names(discovery.chain('markdown', opts)))
    assert.are.same({ 'latex', 'yaml' }, names(discovery.chain('tex', opts)))
  end)

  it('breaks ties on the hook name', function()
    local opts = {
      discovery = { ['*'] = { zulu = function() end, alpha = function() end, mike = function() end } },
    }
    assert.are.same({ 'alpha', 'mike', 'zulu' }, names(discovery.chain('tex', opts)))
  end)
end)

describe('discovery and matcher warnings', function()
  local matchers = require('blink-cmp-bibtex.matchers')

  before_each(function()
    discovery.__test.reset()
  end)

  it('warns separately for a hook and a matcher sharing a name', function()
    -- The two registries share the warn-once bookkeeping, so their keys must be
    -- namespaced or the first warning would silence the second.
    with_notify_capture(function(messages)
      assert.is_nil(discovery.normalize('gapdoc', 42))
      assert.is_nil(matchers.normalize('gapdoc', 42))
      assert.are.equal(2, #messages)
      assert.is_truthy(messages[1]:find('discovery hook', 1, true))
      assert.is_truthy(messages[2]:find('matcher', 1, true))
    end)
  end)

  it('still warns only once per registry for the same name', function()
    with_notify_capture(function(messages)
      discovery.normalize('gapdoc', 42)
      discovery.normalize('gapdoc', 42)
      assert.are.equal(1, #messages)
    end)
  end)

  it('warns separately for a failing hook and a failing matcher of one name', function()
    local opts = {
      discovery = {
        ['*'] = {
          shared = function()
            error('boom')
          end,
        },
      },
      matchers = {
        ['*'] = {
          shared = function()
            error('boom')
          end,
        },
      },
    }
    with_notify_capture(function(messages)
      discovery.collect(ctx(opts, {}, 'tex'))
      matchers.detect('text', opts, { filetype = 'tex' })
      assert.are.equal(2, #messages)
    end)
  end)
end)

describe('discovery.collect', function()
  before_each(function()
    discovery.__test.reset()
  end)

  it('concatenates the results of the chain in order', function()
    local opts = {
      discovery = {
        ['*'] = {
          second = {
            priority = 2,
            find = function()
              return { 'b.bib' }
            end,
          },
          first = {
            priority = 1,
            find = function()
              return { 'a.bib' }
            end,
          },
        },
      },
    }
    assert.are.same({ 'a.bib', 'b.bib' }, discovery.collect(ctx(opts)))
  end)

  it('accepts a bare string as a single result', function()
    local opts = {
      discovery = {
        ['*'] = {
          one = function()
            return 'refs.bib'
          end,
        },
      },
    }
    assert.are.same({ 'refs.bib' }, discovery.collect(ctx(opts)))
  end)

  it('tolerates a hook that reports nothing', function()
    local opts = {
      discovery = {
        ['*'] = {
          none = function()
            return nil
          end,
        },
      },
    }
    assert.are.same({}, discovery.collect(ctx(opts)))
  end)

  it('appends .bib to an extensionless result', function()
    local opts = {
      discovery = {
        ['*'] = {
          one = function()
            return 'refs'
          end,
        },
      },
    }
    assert.are.same({ 'refs.bib' }, discovery.collect(ctx(opts)))
  end)

  it('leaves the result alone when the hook declares extension = false', function()
    local opts = {
      discovery = {
        ['*'] = {
          one = {
            extension = false,
            find = function()
              return 'refs'
            end,
          },
        },
      },
    }
    assert.are.same({ 'refs' }, discovery.collect(ctx(opts)))
  end)

  it('receives a context carrying the buffer, filetype, lines and directory', function()
    local seen
    local opts = {
      discovery = {
        ['*'] = {
          spy = function(context)
            seen = context
            return nil
          end,
        },
      },
    }
    discovery.collect(ctx(opts, { 'a line' }, 'rst'))
    assert.are.equal('rst', seen.filetype)
    assert.are.same({ 'a line' }, seen.lines)
    assert.are.equal('/tmp', seen.dir)
    assert.are.equal(0, seen.bufnr)
    assert.are.equal(opts, seen.opts)
  end)

  it('skips a throwing hook, warns once, and keeps the rest of the chain', function()
    local opts = {
      discovery = {
        ['*'] = {
          broken = {
            priority = 1,
            find = function()
              error('boom')
            end,
          },
          good = {
            priority = 2,
            find = function()
              return 'refs.bib'
            end,
          },
        },
      },
    }
    with_notify_capture(function(messages)
      assert.are.same({ 'refs.bib' }, discovery.collect(ctx(opts)))
      assert.are.same({ 'refs.bib' }, discovery.collect(ctx(opts)))
      assert.are.equal(1, #messages)
    end)
  end)

  it('skips a hook whose result is malformed', function()
    local opts = {
      discovery = {
        ['*'] = {
          bogus = {
            priority = 1,
            find = function()
              return { 'ok.bib', 42 }
            end,
          },
          good = {
            priority = 2,
            find = function()
              return 'refs.bib'
            end,
          },
        },
      },
    }
    with_notify_capture(function(messages)
      assert.are.same({ 'refs.bib' }, discovery.collect(ctx(opts)))
      assert.are.equal(1, #messages)
      assert.is_truthy(messages[1]:find('instead of a file name', 1, true))
    end)
  end)

  it('keeps a hook that failed in one filetype running in another', function()
    local shared = function(context)
      if context.filetype == 'markdown' then
        error('boom')
      end
      return 'refs.bib'
    end
    local opts = { discovery = { ['*'] = { shared = shared } } }
    with_notify_capture(function()
      assert.are.same({}, discovery.collect(ctx(opts, {}, 'markdown')))
      assert.are.same({ 'refs.bib' }, discovery.collect(ctx(opts, {}, 'tex')))
    end)
  end)
end)

describe('discovery built-ins as public functions', function()
  -- Shipped in 0.11.0 as returning file names, and wrapped by users, so the
  -- return type is part of the contract.
  it('return plain file names', function()
    local context = ctx(
      {},
      { '---', 'bibliography: refs.bib', '---', '\\addbibresource{more.bib}', '#bibliography("t.bib")' }
    )
    assert.are.same({ 'more.bib' }, discovery.latex(context))
    assert.are.same({ 'refs.bib' }, discovery.yaml(context))
    assert.are.same({ '/tmp/t.bib' }, discovery.typst(context))
  end)
end)

describe('discovery.collect_detailed', function()
  before_each(function()
    discovery.__test.reset()
  end)

  it('names the hook that reported a bare file name', function()
    local opts = {
      discovery = {
        ['*'] = {
          mine = function()
            return { 'refs' }
          end,
        },
      },
    }
    assert.are.same({ { name = 'refs.bib', hook = 'mine' } }, discovery.collect_detailed(ctx(opts)))
  end)

  it('keeps the line and file a record-form result carries', function()
    local opts = {
      discovery = {
        ['*'] = {
          mine = function()
            return { { name = 'refs.bib', line = 7, file = '/tmp/other.md' } }
          end,
        },
      },
    }
    assert.are.same(
      { { name = 'refs.bib', hook = 'mine', line = 7, file = '/tmp/other.md' } },
      discovery.collect_detailed(ctx(opts))
    )
  end)

  it('applies the extension rule to the name of a record-form result', function()
    local opts = {
      discovery = {
        ['*'] = {
          mine = function()
            return { { name = 'refs', line = 2 } }
          end,
        },
      },
    }
    assert.are.same({ { name = 'refs.bib', hook = 'mine', line = 2 } }, discovery.collect_detailed(ctx(opts)))
  end)

  it('accepts a single record instead of a list', function()
    local opts = {
      discovery = {
        ['*'] = {
          mine = function()
            return { name = 'refs.bib', line = 1 }
          end,
        },
      },
    }
    assert.are.same({ { name = 'refs.bib', hook = 'mine', line = 1 } }, discovery.collect_detailed(ctx(opts)))
  end)

  it('skips a hook returning a record without a name, warning once', function()
    local opts = {
      discovery = {
        ['*'] = {
          bogus = {
            priority = 1,
            find = function()
              return { {} }
            end,
          },
          good = {
            priority = 2,
            find = function()
              return 'refs.bib'
            end,
          },
        },
      },
    }
    with_notify_capture(function(messages)
      assert.are.same({ { name = 'refs.bib', hook = 'good' } }, discovery.collect_detailed(ctx(opts)))
      assert.are.same({ { name = 'refs.bib', hook = 'good' } }, discovery.collect_detailed(ctx(opts)))
      assert.are.equal(1, #messages)
      assert.is_truthy(messages[1]:find('instead of a file name', 1, true))
    end)
  end)

  it('reports the same names as collect, in the same order', function()
    local opts = {
      discovery = {
        ['*'] = {
          second = {
            priority = 2,
            find = function()
              return { { name = 'b.bib', line = 3 } }
            end,
          },
          first = {
            priority = 1,
            find = function()
              return { 'a.bib' }
            end,
          },
        },
      },
    }
    assert.are.same({ 'a.bib', 'b.bib' }, discovery.collect(ctx(opts)))
    local detailed = discovery.collect_detailed(ctx(opts))
    assert.are.same(
      { 'a.bib', 'b.bib' },
      vim.tbl_map(function(entry)
        return entry.name
      end, detailed)
    )
  end)

  it('gives a hook that wraps a built-in the names the built-in returns', function()
    -- The built-in hooks are public and documented as returning file names;
    -- wrapping one must keep working, at the cost of the positions.
    local opts = {
      discovery = {
        ['*'] = {
          wrapper = function(context)
            local found = discovery.latex(context)
            assert.are.same({ 'refs.bib' }, found)
            return found
          end,
        },
      },
    }
    local detailed = discovery.collect_detailed(ctx(opts, { '\\addbibresource{refs.bib}' }))
    assert.are.same({ { name = 'refs.bib', hook = 'wrapper' } }, detailed)
  end)

  it('reports positions for a built-in configured under another name', function()
    local opts = { discovery = { ['*'] = { mine = discovery.latex } } }
    local detailed = discovery.collect_detailed(ctx(opts, { '', '\\addbibresource{refs.bib}' }))
    assert.are.same({ { name = 'refs.bib', hook = 'mine', line = 2 } }, detailed)
  end)

  it('reports the line a LaTeX declaration was found on', function()
    local opts = { discovery = { ['*'] = { latex = true } } }
    local detailed = discovery.collect_detailed(ctx(opts, { '\\documentclass{article}', '\\addbibresource{refs.bib}' }))
    assert.are.same({ { name = 'refs.bib', hook = 'latex', line = 2 } }, detailed)
  end)

  it('reports the line a YAML bibliography key was found on', function()
    local opts = { discovery = { ['*'] = { yaml = true } } }
    local lines = { '---', 'title: doc', 'bibliography:', '  - refs.bib', '---' }
    assert.are.same({ { name = 'refs.bib', hook = 'yaml', line = 4 } }, discovery.collect_detailed(ctx(opts, lines)))
  end)

  it('reports the imported file and line a Typst bibliography was declared in', function()
    helpers.with_tmpdir(function(dir)
      local template = vim.fs.joinpath(dir, 'template.typ')
      helpers.write_file(template, '// header\n#bibliography("refs.bib")\n')
      local opts = { discovery = { ['*'] = { typst = true } } }
      local context = ctx(opts, { '#import "template.typ": *' }, 'typst')
      context.dir = dir
      context.bufname = vim.fs.joinpath(dir, 'main.typ')
      assert.are.same({
        {
          name = vim.fs.joinpath(dir, 'refs.bib'),
          hook = 'typst',
          line = 2,
          file = vim.fs.normalize(template),
        },
      }, discovery.collect_detailed(context))
    end)
  end)

  it('leaves the declaring file unset for a Typst bibliography in the buffer itself', function()
    local opts = { discovery = { ['*'] = { typst = true } } }
    local context = ctx(opts, { '#bibliography("refs.bib")' }, 'typst')
    assert.are.same({ { name = '/tmp/refs.bib', hook = 'typst', line = 1 } }, discovery.collect_detailed(context))
  end)
end)
