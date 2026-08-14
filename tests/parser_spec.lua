--- Characterization tests for the BibTeX and Hayagriva parsers.

local assert = require('luassert')
local parser = require('blink-cmp-bibtex.parser')
local helpers = require('tests.helpers')

--- Index a list of entries by citation key.
--- @param entries table[]
--- @return table<string, table>
local function by_key(entries)
  local map = {}
  for _, entry in ipairs(entries) do
    map[entry.key] = entry
  end
  return map
end

describe('parser.parse', function()
  local entries, keyed

  before_each(function()
    entries = parser.parse_file(helpers.fixture('refs.bib'))
    keyed = by_key(entries)
  end)

  it('parses every entry in the file', function()
    assert.are.equal(4, #entries)
  end)

  it('preserves entry order', function()
    assert.are.same(
      { 'smith2020', 'doe:2019', 'muller-weber.2021', 'nolan2022' },
      vim.tbl_map(function(e)
        return e.key
      end, entries)
    )
  end)

  it('keeps keys containing colons, hyphens and dots intact', function()
    assert.is_not_nil(keyed['doe:2019'])
    assert.is_not_nil(keyed['muller-weber.2021'])
  end)

  it('lowercases the entry type', function()
    assert.are.equal('article', keyed.smith2020.entrytype)
    assert.are.equal('book', keyed['doe:2019'].entrytype)
    assert.are.equal('incollection', keyed['muller-weber.2021'].entrytype)
  end)

  it('parses fields into a lowercased map', function()
    local fields = keyed.smith2020.fields
    assert.are.equal('Smith, Jane and Doe, John', fields.author)
    assert.are.equal('A Study of Things', fields.title)
    assert.are.equal('Journal of Things', fields.journal)
    assert.are.equal('2020', fields.year)
    assert.are.equal('12', fields.volume)
    assert.are.equal('3', fields.number)
    assert.are.equal('45--67', fields.pages)
    assert.are.equal('10.1000/things', fields.doi)
  end)

  it('stores the raw entry text', function()
    local raw = keyed['doe:2019'].raw
    assert.are.equal('@book{doe:2019,', raw:match('^[^\n]+'))
    assert.are.equal('}', raw:sub(-1))
  end)
end)

describe('parser LaTeX normalization', function()
  local keyed

  before_each(function()
    keyed = by_key(parser.parse_file(helpers.fixture('accents.bib')))
  end)

  it('skips @string and @comment blocks', function()
    assert.is_nil(keyed.jot)
    assert.are.equal(5, vim.tbl_count(keyed))
  end)

  it('skips a @comment block whose prose looks like a key', function()
    -- Regression: these blocks used to be parsed by shape, so prose starting
    -- 'Note, ...' produced a bogus entry with the key 'Note'.
    assert.are.same({}, parser.parse('@comment{Note, that Smith says}'))
  end)

  it('skips @string and @preamble blocks with a key-like shape', function()
    assert.are.same({}, parser.parse('@STRING{jot, "Journal of Things"}'))
    assert.are.same({}, parser.parse('@preamble{macro, "\\newcommand"}'))
  end)

  it('keeps parsing entries that follow a skipped block', function()
    local entries = parser.parse('@comment{Note, ignored}\n@article{after2020, title = {After}}')
    assert.are.equal(1, #entries)
    assert.are.equal('after2020', entries[1].key)
  end)

  it('converts umlaut accents to UTF-8', function()
    assert.are.equal('Möller, Sören', keyed.umlaut2020.fields.author)
    assert.are.equal('Über die Ströme', keyed.umlaut2020.fields.title)
  end)

  it('converts acute accents to UTF-8', function()
    assert.are.equal('André, René', keyed.acute2021.fields.author)
    assert.are.equal('Café Culture', keyed.acute2021.fields.title)
  end)

  it('reads quoted field values', function()
    assert.are.equal('Quoted Journal Name', keyed.acute2021.fields.journal)
    assert.are.equal('2021', keyed.acute2021.fields.year)
  end)

  it('expands braced simple commands such as {\\ss}', function()
    assert.are.equal('Weiß, Hans', keyed.sharps2019.fields.author)
    assert.are.equal('Die Grße Straße', keyed.sharps2019.fields.title)
  end)

  it('expands \\aa and \\AA', function()
    assert.are.equal('På Resa', keyed.nordic2018.fields.title)
    assert.are.equal('Förlaget', keyed.nordic2018.fields.publisher)
  end)

  it('leaves a space when a simple command is separated by whitespace', function()
    -- current behavior (quirk): '\AA sa' consumes the command name but not the
    -- separating space, yielding 'Å sa' rather than 'Åsa'.
    assert.are.equal('Åberg, Å sa', keyed.nordic2018.fields.author)
  end)

  it('strips nested and wrapper braces', function()
    assert.are.equal('The LaTeX and Nested Braces', keyed.nested2017.fields.title)
    assert.are.equal('Typesetting Matters', keyed.nested2017.fields.booktitle)
  end)
end)

describe('parser.parse_file', function()
  it('throws for a missing path', function()
    -- current behavior: the error is raised, and cache.load_file is what wraps
    -- the call in pcall so the editor never sees it.
    local ok, err = pcall(parser.parse_file, helpers.fixture('does_not_exist.bib'))
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find('Cannot open file', 1, true))
  end)

  it('dispatches on extension to the Hayagriva parser', function()
    local entries = parser.parse_file(helpers.fixture('refs.yml'))
    assert.are.equal(2, #entries)
  end)
end)

describe('parser.parse_hayagriva', function()
  local keyed

  before_each(function()
    keyed = by_key(parser.parse_file(helpers.fixture('refs.yml')))
  end)

  it('uses the top-level YAML key as the citation key', function()
    assert.is_not_nil(keyed['hayagriva-one'])
    assert.is_not_nil(keyed['hayagriva-two'])
  end)

  it('joins author sequences with " and "', function()
    assert.are.equal('Lindgren, Astrid and Blyton, Enid', keyed['hayagriva-one'].fields.author)
  end)

  it('maps date to year', function()
    assert.are.equal('2021', keyed['hayagriva-one'].fields.year)
    assert.are.equal('1954', keyed['hayagriva-two'].fields.year)
  end)

  it('strips surrounding quotes from scalar values', function()
    assert.are.equal('A Hayagriva Book', keyed['hayagriva-two'].fields.title)
    assert.are.equal('Tolkien, J. R. R.', keyed['hayagriva-two'].fields.author)
    assert.are.equal('Allen and Unwin', keyed['hayagriva-two'].fields.publisher)
  end)

  it('uses the type field as entrytype without lowercasing it', function()
    assert.are.equal('Book', keyed['hayagriva-two'].entrytype)
  end)

  it('flattens nested mappings into the parent entry', function()
    -- current behavior (quirk): 'parent:' has an empty value, so it is treated
    -- as the start of a sequence; the indented keys below it are then parsed as
    -- fields of the entry itself and overwrite title and type.
    assert.are.equal('The Periodical', keyed['hayagriva-one'].fields.title)
    assert.are.equal('Periodical', keyed['hayagriva-one'].entrytype)
  end)

  it('stores the raw YAML block per entry', function()
    local raw = keyed['hayagriva-two'].raw
    assert.are.equal('hayagriva-two:', raw:match('^[^\n]+'))
    assert.is_truthy(raw:find('publisher: Allen and Unwin', 1, true))
  end)
end)
