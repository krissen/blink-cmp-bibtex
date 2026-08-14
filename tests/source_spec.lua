--- Integration tests for the blink.cmp source surface.

local assert = require('luassert')
local Source = require('blink-cmp-bibtex')
local cache = require('blink-cmp-bibtex.cache')
local helpers = require('tests.helpers')

--- Drive Source:get_completions synchronously.
--- @param source table The source instance
--- @param context table A blink.cmp-shaped context
--- @return table The response passed to the callback
local function complete(source, context)
  local response
  source:get_completions(context, function(result)
    response = result
  end)
  vim.wait(2000, function()
    return response ~= nil
  end)
  assert.is_not_nil(response, 'get_completions never invoked its callback')
  return response
end

--- Collect the labels of a response.
--- @param response table
--- @return string[]
local function labels(response)
  return vim.tbl_map(function(item)
    return item.label
  end, response.items)
end

describe('Source:get_completions', function()
  local bufnr, source

  before_each(function()
    bufnr = vim.fn.bufadd(helpers.fixture('project/main.tex'))
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_option_value('filetype', 'tex', { buf = bufnr })
    source = Source.new({ files = { helpers.fixture('project/bib/refs.bib') } })
    cache.invalidate(helpers.fixture('project/bib/refs.bib'))
  end)

  it('completes citation keys inside \\cite{}', function()
    local response = complete(source, helpers.ctx('\\cite{', nil, bufnr))
    table.sort(labels(response))
    assert.are.same({ 'project2020', 'projectbook2018' }, vim.fn.sort(labels(response)))
  end)

  it('filters by the typed prefix', function()
    local response = complete(source, helpers.ctx('\\cite{projectb', nil, bufnr))
    assert.are.same({ 'projectbook2018' }, labels(response))
  end)

  it('filters by the last key of a multi-key citation', function()
    local response = complete(source, helpers.ctx('\\cite{project2020,projectb', nil, bufnr))
    assert.are.same({ 'projectbook2018' }, labels(response))
  end)

  it('sets insertText to the citation key and marks the list incomplete', function()
    local response = complete(source, helpers.ctx('\\cite{projectb', nil, bufnr))
    local item = response.items[1]
    assert.are.equal('projectbook2018', item.insertText)
    assert.are.equal('projectbook2018', item.label)
    assert.are.equal('blink-cmp-bibtex', item.data.source)
    assert.are.equal('projectbook2018', item.data.key)
    assert.is_true(response.is_incomplete_forward)
    assert.is_true(response.is_incomplete_backward)
  end)

  it('renders an APA detail line', function()
    local response = complete(source, helpers.ctx('\\cite{project2020', nil, bufnr))
    assert.are.equal('Project, Pat (2020) – A Project Local Reference (Project Journal)', response.items[1].detail)
  end)

  it('renders an IEEE detail line when configured', function()
    local ieee = Source.new({
      files = { helpers.fixture('project/bib/refs.bib') },
      preview_style = 'ieee',
    })
    local response = complete(ieee, helpers.ctx('\\cite{project2020', nil, bufnr))
    assert.is_truthy(response.items[1].detail:find('"A Project Local Reference,"', 1, true))
  end)

  it('returns an empty response outside a citation context', function()
    local response = complete(source, helpers.ctx('plain prose here', nil, bufnr))
    assert.are.same({}, response.items)
    assert.is_false(response.is_incomplete_forward)
  end)

  it('returns an empty response when no bib files resolve', function()
    local bare = Source.new({ files = {}, search_paths = {}, root_markers = {} })
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('filetype', 'tex', { buf = scratch })
    local response = complete(bare, helpers.ctx('\\cite{', nil, scratch))
    assert.are.same({}, response.items)
    vim.api.nvim_buf_delete(scratch, { force = true })
  end)

  it('returns an empty response for a filetype outside the configured list', function()
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('filetype', 'python', { buf = scratch })
    local response = complete(source, helpers.ctx('\\cite{', nil, scratch))
    assert.are.same({}, response.items)
    assert.is_false(response.is_incomplete_forward)
    vim.api.nvim_buf_delete(scratch, { force = true })
  end)

  it('discovers bib files from the buffer without explicit configuration', function()
    local discovered = Source.new({ files = {} })
    local response = complete(discovered, helpers.ctx('\\cite{projectb', nil, bufnr))
    assert.are.same({ 'projectbook2018' }, labels(response))
  end)

  it('honours max_entries', function()
    local limited = Source.new({
      files = { helpers.fixture('project/bib/refs.bib') },
      max_entries = 1,
    })
    local response = complete(limited, helpers.ctx('\\cite{', nil, bufnr))
    assert.are.equal(1, #response.items)
  end)

  it('deduplicates keys present in several files', function()
    local duplicated = Source.new({
      files = {
        helpers.fixture('project/bib/refs.bib'),
        helpers.fixture('project/bib/refs.bib'),
      },
    })
    local response = complete(duplicated, helpers.ctx('\\cite{project2020', nil, bufnr))
    assert.are.equal(1, #response.items)
  end)
end)

describe('Source source indicators', function()
  local bufnr

  before_each(function()
    bufnr = vim.fn.bufadd(helpers.fixture('project/main.tex'))
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_option_value('filetype', 'tex', { buf = bufnr })
  end)

  it('omits labelDetails when every entry comes from one origin', function()
    local source = Source.new({ files = { helpers.fixture('project/bib/refs.bib') } })
    local response = complete(source, helpers.ctx('\\cite{project2020', nil, bufnr))
    assert.is_nil(response.items[1].labelDetails)
  end)

  it('marks local-only entries with [L] when sources are mixed', function()
    local source = Source.new({
      files = { helpers.fixture('project/bib/refs.bib') },
      global_files = { helpers.fixture('refs.bib') },
    })
    local response = complete(source, helpers.ctx('\\cite{project2020', nil, bufnr))
    assert.are.same({ description = '[L]' }, response.items[1].labelDetails)
  end)

  it('marks global-only entries with [G] when sources are mixed', function()
    local source = Source.new({
      files = { helpers.fixture('project/bib/refs.bib') },
      global_files = { helpers.fixture('refs.bib') },
    })
    local response = complete(source, helpers.ctx('\\cite{smith2020', nil, bufnr))
    assert.are.same({ description = '[G]' }, response.items[1].labelDetails)
  end)
end)

describe('Source GAPDoc support', function()
  local bufnr, source

  before_each(function()
    bufnr = vim.fn.bufadd(helpers.fixture('project/doc.xml'))
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_option_value('filetype', 'gap', { buf = bufnr })
    source = Source.new({
      files = { helpers.fixture('project/bib/refs.bib') },
      filetypes = { 'gap' },
    })
    cache.invalidate(helpers.fixture('project/bib/refs.bib'))
  end)

  it('completes citation keys inside <Cite Key="', function()
    local response = complete(source, helpers.ctx('As shown in <Cite Key="', nil, bufnr))
    assert.are.same({ 'project2020', 'projectbook2018' }, vim.fn.sort(labels(response)))
  end)

  it('filters by the typed prefix', function()
    local response = complete(source, helpers.ctx('<Cite Key="projectb', nil, bufnr))
    assert.are.same({ 'projectbook2018' }, labels(response))
  end)

  it('leaves a comma in the prefix unsanitized', function()
    -- GAPDoc keys are used verbatim, so 'a,b' must not be narrowed to 'b'.
    local response = complete(source, helpers.ctx('<Cite Key="project2020,projectb', nil, bufnr))
    assert.are.same({}, response.items)
  end)

  it('returns an empty response once the attribute is closed', function()
    local response = complete(source, helpers.ctx('<Cite Key="project2020"/>', nil, bufnr))
    assert.are.same({}, response.items)
  end)

  it('is enabled in a gap buffer and reports the quote as a trigger character', function()
    vim.api.nvim_buf_call(bufnr, function()
      assert.is_true(source:enabled())
      assert.are.same({ '"' }, source:get_trigger_characters())
    end)
  end)

  it('is disabled in filetypes outside the configured list', function()
    local scratch = helpers.make_buf({ lines = {}, filetype = 'python' })
    vim.api.nvim_buf_call(scratch, function()
      assert.is_false(source:enabled())
    end)
    vim.api.nvim_buf_delete(scratch, { force = true })
  end)
end)

describe('Source:get_trigger_characters', function()
  it('is empty for the default citation filetypes', function()
    local source = Source.new({})
    local scratch = helpers.make_buf({ lines = {}, filetype = 'tex' })
    vim.api.nvim_buf_call(scratch, function()
      assert.are.same({}, source:get_trigger_characters())
      assert.is_true(source:enabled())
    end)
    vim.api.nvim_buf_delete(scratch, { force = true })
  end)
end)

describe('Source:resolve', function()
  it('passes the item through unchanged', function()
    local source = Source.new({})
    local item = { label = 'x' }
    local resolved
    source:resolve(item, function(result)
      resolved = result
    end)
    assert.are.equal(item, resolved)
  end)
end)
