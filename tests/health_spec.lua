--- Tests for the checkhealth report.

local assert = require('luassert')
local config = require('blink-cmp-bibtex.config')
local health = require('blink-cmp-bibtex.health')
local helpers = require('tests.helpers')

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
  local previous_buf
  local scratch_buffers

  --- Make a scratch buffer current, remembering it for cleanup.
  --- @param opts table Passed to helpers.make_buf
  --- @return number bufnr
  local function use_buffer(opts)
    local bufnr = helpers.make_buf(opts)
    scratch_buffers[#scratch_buffers + 1] = bufnr
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    previous_buf = vim.api.nvim_get_current_buf()
    scratch_buffers = {}
    -- The report describes the current buffer, so every test starts from a
    -- buffer of a filetype the source is offered in.
    use_buffer({ lines = {}, filetype = 'tex' })
  end)

  after_each(function()
    config.setup(nil)
    if vim.api.nvim_buf_is_valid(previous_buf) then
      vim.api.nvim_set_current_buf(previous_buf)
    end
    for _, bufnr in ipairs(scratch_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
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

  it('reports the discovery chain', function()
    config.setup(nil)
    local message = assert(find(run_check().info, 'latex (priority 10), yaml (priority 20)'))
    assert.is_truthy(message:find('typst (priority 30), gapdoc (priority 40)', 1, true))
  end)

  it('reports the shipped GAP package hook as dormant rather than broken', function()
    config.setup(nil)
    local calls = run_check()
    for _, filetype in ipairs({ 'gap', 'xml', 'autodoc' }) do
      -- The matcher section reports the same filetypes, so the line is picked
      -- by the hook it names rather than by the filetype alone.
      local message =
        assert(find(calls.info, filetype .. ': latex (priority 10)'), 'no discovery line for ' .. filetype)
      assert.is_truthy(message:find('gapdoc (priority 40), gap_package (priority 45)', 1, true))
      assert.is_truthy(message:find('dormant', 1, true))
      assert.is_nil(find(calls.warn, filetype))
    end
  end)

  it('warns when buffer discovery is turned off', function()
    config.setup({ discovery = false })
    assert.is_truthy(find(run_check().warn, 'buffer discovery is disabled'))
  end)

  it('warns about discovery hooks for a filetype outside the filetypes list', function()
    config.setup({ discovery = { rst = { mine = function() end } } })
    local message = assert(find(run_check().warn, "discovery for 'rst'"))
    assert.is_truthy(message:find('bibliographies will not be discovered there', 1, true))
  end)

  it('still reports discovery when no matchers are configured', function()
    -- The matcher section used to return early, which hid everything below it.
    local original = config.get
    --- @diagnostic disable-next-line: duplicate-set-field
    config.get = function()
      local resolved = vim.deepcopy(original())
      resolved.matchers = {}
      return resolved
    end
    local ok, calls = pcall(run_check)
    config.get = original
    assert.is_true(ok, tostring(calls))
    assert.is_truthy(find(calls.warn, 'no matchers are configured'))
    assert.is_truthy(find(calls.info, 'latex (priority 10), yaml (priority 20)'))
  end)

  it('warns about matchers for a filetype outside the filetypes list', function()
    config.setup({ matchers = { cobol = { latex = true } } })
    assert.is_truthy(find(run_check().warn, "matchers for 'cobol'"))
  end)
end)

describe('health.check bibliographies', function()
  local previous_buf
  local scratch_buffers

  --- Make a scratch buffer current, remembering it for cleanup.
  --- @param opts table Passed to helpers.make_buf
  --- @return number bufnr
  local function use_buffer(opts)
    local bufnr = helpers.make_buf(opts)
    scratch_buffers[#scratch_buffers + 1] = bufnr
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    previous_buf = vim.api.nvim_get_current_buf()
    scratch_buffers = {}
  end)

  after_each(function()
    config.setup(nil)
    if vim.api.nvim_buf_is_valid(previous_buf) then
      vim.api.nvim_set_current_buf(previous_buf)
    end
    for _, bufnr in ipairs(scratch_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it('lists a bibliography discovered from the buffer with its hook and line', function()
    helpers.with_tmpdir(function(dir)
      helpers.write_file(vim.fs.joinpath(dir, 'refs.bib'), '@article{a,\n  title = {A}\n}\n')
      use_buffer({
        lines = { '\\addbibresource{refs.bib}' },
        name = vim.fs.joinpath(dir, 'main.tex'),
        filetype = 'tex',
      })
      config.setup(nil)
      local calls = run_check()
      assert.is_truthy(find(calls.start, 'blink-cmp-bibtex: bibliographies'))
      assert.is_truthy(find(calls.info, 'current buffer: '))
      assert.is_truthy(find(calls.ok, 'refs.bib (buffer discovery: latex, main.tex:1)'))
      assert.is_truthy(find(calls.info, 'provider-level opts'))
    end)
  end)

  it('lists a global bibliography before the local ones', function()
    helpers.with_tmpdir(function(dir)
      helpers.write_file(vim.fs.joinpath(dir, 'refs.bib'), '')
      helpers.write_file(vim.fs.joinpath(dir, 'global.bib'), '')
      use_buffer({
        lines = { '\\addbibresource{refs.bib}' },
        name = vim.fs.joinpath(dir, 'main.tex'),
        filetype = 'tex',
      })
      config.setup({ global_files = { vim.fs.joinpath(dir, 'global.bib') } })
      local calls = run_check()
      assert.is_truthy(find(calls.ok, 'global: '))
      assert.is_truthy(find(calls.ok, 'global.bib (global_files)'))
      local global_index, local_index
      for index, message in ipairs(calls.ok) do
        global_index = global_index or (message:find('global: ', 1, true) and index)
        local_index = local_index or (message:find('local: ', 1, true) and index)
      end
      assert.is_true(global_index < local_index)
    end)
  end)

  it('warns about a configured file that does not exist', function()
    helpers.with_tmpdir(function(dir)
      use_buffer({ lines = {}, filetype = 'tex' })
      config.setup({ files = { vim.fs.joinpath(dir, 'nope.bib') } })
      local message = assert(find(run_check().warn, 'missing: '))
      assert.is_truthy(message:find('nope.bib (files)', 1, true))
      assert.is_truthy(message:find('does not exist', 1, true))
    end)
  end)

  it('warns about a configured path that is a directory', function()
    helpers.with_tmpdir(function(dir)
      use_buffer({ lines = {}, filetype = 'tex' })
      config.setup({ files = { dir } })
      assert.is_truthy(find(run_check().warn, 'is a directory'))
    end)
  end)

  it('warns when the buffer filetype is not one the source is offered in', function()
    use_buffer({ lines = {}, filetype = 'python' })
    config.setup(nil)
    local message = assert(find(run_check().warn, "filetype 'python' is not in filetypes"))
    assert.is_truthy(message:find('the list below is what it would use', 1, true))
  end)

  it('reports that nothing resolves for a buffer without bibliographies', function()
    use_buffer({ lines = {}, filetype = 'tex' })
    config.setup(nil)
    assert.is_truthy(find(run_check().info, 'no bibliographies resolve for this buffer'))
  end)

  it('reports on the alternate buffer when the report itself is current', function()
    helpers.with_tmpdir(function(dir)
      helpers.write_file(vim.fs.joinpath(dir, 'refs.bib'), '')
      use_buffer({
        lines = { '\\addbibresource{refs.bib}' },
        name = vim.fs.joinpath(dir, 'main.tex'),
        filetype = 'tex',
      })
      use_buffer({ lines = {}, filetype = 'checkhealth' })
      config.setup(nil)
      local calls = run_check()
      assert.is_truthy(find(calls.info, 'main.tex'))
      assert.is_truthy(find(calls.ok, 'refs.bib (buffer discovery: latex, main.tex:1)'))
    end)
  end)
end)
