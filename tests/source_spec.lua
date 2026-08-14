--- Integration tests for the blink.cmp source surface.

local assert = require('luassert')
local Source = require('blink-cmp-bibtex')
local cache = require('blink-cmp-bibtex.cache')
local config = require('blink-cmp-bibtex.config')
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
    -- shared2015 comes from the <Bibliography Databases="shared"/> declaration
    -- in doc.xml, which is discovered from the buffer, not from opts.files.
    assert.are.same({ 'project2020', 'projectbook2018', 'shared2015' }, vim.fn.sort(labels(response)))
  end)

  it('completes from the declared bibliography without any configured files', function()
    local discovered = Source.new({ files = {}, filetypes = { 'gap' } })
    local response = complete(discovered, helpers.ctx('<Cite Key="shared', nil, bufnr))
    assert.are.same({ 'shared2015' }, labels(response))
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

describe('Source entry lookup lifetime', function()
  local bufnr, dir, bib

  before_each(function()
    dir = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(dir, 'p')
    bib = vim.fs.joinpath(dir, 'refs.bib')
    local entries = {}
    for index = 1, 5 do
      table.insert(entries, string.format('@article{aaa%d,\n  title = {A %d}\n}', index, index))
      table.insert(entries, string.format('@article{bbb%d,\n  title = {B %d}\n}', index, index))
    end
    helpers.write_file(bib, table.concat(entries, '\n'))
    cache.invalidate(bib)
    bufnr = helpers.make_buf({ lines = { '' }, filetype = 'tex' })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(dir, 'rf')
  end)

  it('keeps only the latest round in the lookup instead of accumulating keys', function()
    local source = Source.new({ files = { bib } })
    complete(source, helpers.ctx('\\cite{aaa', nil, bufnr))
    assert.are.equal(5, vim.tbl_count(Source.get_entry_lookup()))

    complete(source, helpers.ctx('\\cite{bbb', nil, bufnr))
    local lookup = Source.get_entry_lookup()
    assert.are.equal(5, vim.tbl_count(lookup))
    assert.is_nil(lookup.aaa1, 'a key from the previous round is still in the current one')
    assert.is_not_nil(lookup.bbb1)
  end)

  it('does not grow across many rounds', function()
    local source = Source.new({ files = { bib } })
    for _ = 1, 20 do
      complete(source, helpers.ctx('\\cite{aaa', nil, bufnr))
      complete(source, helpers.ctx('\\cite{bbb', nil, bufnr))
    end
    assert.are.equal(5, vim.tbl_count(Source.get_entry_lookup()))
  end)
end)

describe('Source:execute auto_add', function()
  local bufnr, dir, global_bib, target

  --- Drive Source:execute synchronously.
  --- @param source table
  --- @param key string
  local function accept(source, key)
    local done = false
    source:execute({ bufnr = bufnr }, { data = { key = key } }, function()
      done = true
    end, nil)
    vim.wait(2000, function()
      return done
    end)
    assert.is_true(done, 'execute never invoked its callback')
  end

  before_each(function()
    dir = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(dir, 'p')
    global_bib = vim.fs.joinpath(dir, 'global.bib')
    target = vim.fs.joinpath(dir, 'local.bib')
    helpers.write_file(global_bib, '@article{aaa1,\n  title = {A 1}\n}\n@article{bbb1,\n  title = {B 1}\n}')
    helpers.write_file(target, '')
    cache.invalidate(global_bib)
    bufnr = helpers.make_buf({ lines = { '' }, filetype = 'tex' })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(dir, 'rf')
  end)

  --- @return table
  local function make_source()
    return Source.new({
      files = { global_bib },
      global_files = { global_bib },
      local_bib = { enabled = true, auto_add = true, target = target, notify_on_add = false },
    })
  end

  --- @return string
  local function read_target()
    local fd = assert(io.open(target, 'r'))
    local content = fd:read('*a')
    fd:close()
    return content
  end

  it('copies the accepted entry to the local bib', function()
    local source = make_source()
    complete(source, helpers.ctx('\\cite{aaa', nil, bufnr))
    accept(source, 'aaa1')
    assert.is_truthy(read_target():find('@article{aaa1', 1, true))
  end)

  it('still resolves the accepted entry when a new round has already run', function()
    -- The round that produced the item is retained one generation, so an accept
    -- that lands after the next round has started still finds its entry.
    local source = make_source()
    complete(source, helpers.ctx('\\cite{aaa', nil, bufnr))
    complete(source, helpers.ctx('\\cite{bbb', nil, bufnr))
    accept(source, 'aaa1')
    assert.is_truthy(read_target():find('@article{aaa1', 1, true))
  end)
end)

describe('Source.__test.key_under_cursor', function()
  local bufnr

  --- Place the cursor in a scratch buffer and detect the key under it.
  --- @param filetype string
  --- @param line string Cursor position is marked with '|'
  --- @param opts table|nil Configuration options
  --- @return string|nil
  local function detect(filetype, line, opts)
    local col = assert(line:find('|', 1, true), 'the line must mark the cursor with |') - 1
    bufnr = helpers.make_buf({ lines = { (line:gsub('%|', '')) }, filetype = filetype })
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, col })
    return Source.__test.key_under_cursor(bufnr, opts or config.get())
  end

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('detects a key the cursor sits inside of in a LaTeX citation', function()
    assert.are.equal('smith2020', detect('tex', '\\cite{smi|th2020} and more'))
  end)

  it('detects a key the cursor sits at the end of', function()
    assert.are.equal('smith2020', detect('tex', '\\cite{smith202|0}'))
  end)

  it('detects the key being pointed at in a multi-key citation', function()
    assert.are.equal('doe2019', detect('tex', '\\cite{smith2020,do|e2019}'))
  end)

  it('detects a Pandoc key', function()
    assert.are.equal('smith2020', detect('markdown', 'see [@smi|th2020] here'))
  end)

  it('detects a GAPDoc key, which the ad-hoc patterns never covered', function()
    assert.are.equal('smith2020', detect('gap', '<Cite Key="smi|th2020"/>'))
  end)

  it('detects a key through a user-registered matcher', function()
    local opts = vim.deepcopy(config.get())
    opts.matchers = vim.deepcopy(opts.matchers)
    opts.matchers.xml = {
      refkey = {
        priority = 5,
        sanitize = false,
        match = function(text)
          local prefix = text:match('<Ref%s+BibKey="([^"]*)$')
          return prefix and { prefix = prefix, trigger = 'refkey' } or nil
        end,
      },
    }
    assert.are.equal('smith2020', detect('xml', '<Ref BibKey="smi|th2020"/>', opts))
  end)

  it('keeps a slash inside the key', function()
    assert.are.equal('smith/2020', detect('tex', '\\cite{smi|th/2020}'))
  end)

  it('keeps a plus inside a GAPDoc key', function()
    assert.are.equal('a+b', detect('gap', '<Cite Key="a|+b"/>'))
  end)

  it('keeps punctuation the parser accepts in a key', function()
    -- The parser takes any run of non-comma, non-whitespace characters, so the
    -- cursor scan must not stop at the first character outside a short alphabet.
    assert.are.equal('a/b+c~d!e', detect('tex', '\\cite{a/b|+c~d!e}'))
  end)

  it('still stops at the delimiter that ends the citation', function()
    assert.are.equal('smith2020', detect('markdown', 'see [@smi|th2020] and more'))
  end)

  it('returns nil for a plain word', function()
    assert.is_nil(detect('markdown', 'just some wo|rds here'))
  end)

  it('returns nil once the citation is closed behind the cursor', function()
    assert.is_nil(detect('tex', '\\cite{smith2020}|'))
  end)
end)
