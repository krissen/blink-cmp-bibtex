--- Tests for the checkhealth report.

local assert = require('luassert')
local config = require('blink-cmp-bibtex.config')
local health = require('blink-cmp-bibtex.health')

--- Run health.check() with the reporters replaced by recorders.
--- @return table { start: string[], ok: string[], warn: string[], info: string[] }
local function run_check()
  local calls = { start = {}, ok = {}, warn = {}, info = {} }
  local original = vim.health
  local function recorder(kind)
    return function(message)
      table.insert(calls[kind], message)
    end
  end
  vim.health = {
    start = recorder('start'),
    ok = recorder('ok'),
    warn = recorder('warn'),
    info = recorder('info'),
  }
  local ok, err = pcall(health.check)
  vim.health = original
  assert.is_true(ok, tostring(err))
  return calls
end

--- Find the first recorded message containing a fragment.
--- @param messages string[]
--- @param fragment string
--- @return string|nil
local function find(messages, fragment)
  for _, message in ipairs(messages) do
    if message:find(fragment, 1, true) then
      return message
    end
  end
  return nil
end

describe('health.check', function()
  after_each(function()
    config.setup(nil)
  end)

  it('reports a clean default configuration', function()
    config.setup(nil)
    local calls = run_check()
    assert.are.same({}, calls.warn)
    assert.is_truthy(find(calls.ok, 'filetypes: tex'))
    assert.is_truthy(find(calls.info, 'files: 0 configured'))
  end)

  it('counts a bare string file option as one file', function()
    config.setup({ files = 'refs.bib' })
    assert.is_truthy(find(run_check().info, 'files: 1 configured'))
  end)

  it('counts the files returned by a function option', function()
    config.setup({
      files = function()
        return { 'a.bib', 'b.bib' }
      end,
      global_files = function()
        return 'global.bib'
      end,
    })
    local calls = run_check()
    assert.is_truthy(find(calls.info, 'files: 2 configured'))
    assert.is_truthy(find(calls.info, 'global_files: 1 configured'))
  end)

  it('degrades gracefully when a function option raises', function()
    config.setup({
      files = function()
        error('boom')
      end,
    })
    assert.is_truthy(find(run_check().info, 'files: 0 configured'))
  end)

  it('reports the shipped GAPDoc filetypes as dormant rather than broken', function()
    config.setup(nil)
    local calls = run_check()
    for _, filetype in ipairs({ 'gap', 'xml', 'autodoc' }) do
      local message = assert(find(calls.info, filetype .. ': '), 'no info line for ' .. filetype)
      assert.is_truthy(message:find('dormant', 1, true))
      assert.is_truthy(message:find('gapdoc (priority 5)', 1, true))
      assert.is_nil(find(calls.warn, filetype))
    end
  end)

  it('reports an enabled matcher filetype as OK with its chain', function()
    config.setup({ filetypes = { 'tex', 'gap' } })
    local calls = run_check()
    local message = assert(find(calls.ok, 'gap: '), 'no ok line for gap')
    assert.is_truthy(message:find('gapdoc (priority 5)', 1, true))
    assert.are.same({}, calls.warn)
  end)

  it('reports the shared chain', function()
    config.setup(nil)
    local message = assert(find(run_check().info, 'shared'))
    assert.is_truthy(message:find('latex (priority 10), pandoc (priority 30)', 1, true))
  end)

  it('warns when no matchers are configured at all', function()
    -- Not reachable through setup(), which always merges the shipped matchers
    -- back in, so the options are stubbed to reach the defensive branch.
    local original = config.get
    --- @diagnostic disable-next-line: duplicate-set-field
    config.get = function()
      local opts = vim.deepcopy(original())
      opts.matchers = {}
      return opts
    end
    local ok, calls = pcall(run_check)
    config.get = original
    assert.is_true(ok, tostring(calls))
    assert.is_truthy(find(calls.warn, 'no matchers are configured'))
  end)

  it('warns about matchers for a filetype outside the filetypes list', function()
    config.setup({ matchers = { cobol = { latex = true } } })
    assert.is_truthy(find(run_check().warn, "matchers for 'cobol'"))
  end)
end)
