--- Buffer bibliography discovery for blink-cmp-bibtex
--- A discovery hook reads a buffer and reports the bibliography files it
--- declares. The hooks shipped here understand LaTeX, Markdown YAML front
--- matter, Typst and GAPDoc; users register their own through the discovery
--- option. This module never requires the config module; it only receives opts.
--- @module 'blink-cmp-bibtex.discovery'

local path_util = require('blink-cmp-bibtex.path')
local registry = require('blink-cmp-bibtex.registry')

local M = {}

--- What a discovery hook is given
--- The lines table is shared between hooks and must be treated as read-only.
--- @class BibtexDiscoveryContext
--- @field bufnr number The buffer being scanned
--- @field filetype string|nil The buffer filetype
--- @field lines string[] The buffer lines, read-only
--- @field bufname string|nil The buffer file name, empty for scratch buffers
--- @field dir string|nil The buffer's directory, for resolving relative paths
--- @field opts table Configuration options

--- A discovery hook
--- Unlike a matcher, a hook takes no subject argument: the lines it reads are
--- already part of the context.
--- @alias BibtexDiscoveryFn fun(ctx: BibtexDiscoveryContext): string[]|string|nil

--- A normalized discovery entry
--- @class BibtexDiscoverySpec
--- @field name string The hook name
--- @field find BibtexDiscoveryFn The hook itself
--- @field priority number Lower runs first (default 50); affects output order only
--- @field extension boolean|nil When not false, extensionless results get '.bib'

--- Default priority for hooks that do not declare one
--- @type number
local DEFAULT_PRIORITY = 50

--- BibTeX bibliography command names to recognize
--- @type table<string, boolean>
local bibliography_commands = {
  addbibresource = true,
  ['addbibresource*'] = true,
  addglobalbib = true,
  addsectionbib = true,
  bibliography = true,
  nobibliography = true,
}

--- Trim whitespace from a string
--- @param value string The string to trim
--- @return string The trimmed string
local function trim(value)
  return value:match('^%s*(.-)%s*$') or ''
end

--- Split a comma-separated resource string into individual entries
--- @param value string The resource string to split
--- @return string[] List of resource names
local function split_resources(value)
  local entries = {}
  for part in value:gmatch('[^,]+') do
    local cleaned = trim(part)
    if cleaned ~= '' then
      entries[#entries + 1] = cleaned
    end
  end
  if #entries == 0 and value ~= '' then
    entries[1] = trim(value)
  end
  return entries
end

--- Skip whitespace in a string starting from a given index
--- @param str string The input string
--- @param idx number Starting index
--- @return number The next non-whitespace index
local function skip_whitespace(str, idx)
  while idx <= #str and str:sub(idx, idx):match('%s') do
    idx = idx + 1
  end
  return idx
end

--- Read a balanced block (e.g., braces) from a string
--- @param str string The input string
--- @param idx number Starting index
--- @return string|nil, number The extracted block and next index
local function read_balanced_block(str, idx)
  if str:sub(idx, idx) ~= '{' then
    return nil, idx
  end
  local depth = 1
  local cursor = idx + 1
  while cursor <= #str and depth > 0 do
    local ch = str:sub(cursor, cursor)
    if ch == '{' then
      depth = depth + 1
    elseif ch == '}' then
      depth = depth - 1
      if depth == 0 then
        return str:sub(idx + 1, cursor - 1), cursor + 1
      end
    elseif ch == '\\' and cursor < #str then
      cursor = cursor + 1
    end
    cursor = cursor + 1
  end
  return nil, idx
end

--- Skip optional arguments in a LaTeX command
--- @param str string The input string
--- @param idx number Starting index
--- @return number The index after all optional arguments
local function skip_optional_arguments(str, idx)
  local cursor = skip_whitespace(str, idx)
  while str:sub(cursor, cursor) == '[' do
    local depth = 1
    cursor = cursor + 1
    while cursor <= #str and depth > 0 do
      local ch = str:sub(cursor, cursor)
      if ch == '[' then
        depth = depth + 1
      elseif ch == ']' then
        depth = depth - 1
      end
      cursor = cursor + 1
    end
    cursor = skip_whitespace(str, cursor)
  end
  return cursor
end

--- Extract bibliography file paths from a LaTeX command line
--- @param line string The line to parse
--- @return string[] List of extracted file paths
local function extract_command_paths(line)
  local results = {}
  local i = 1
  while i <= #line do
    local start_pos, end_pos, command = line:find('\\([%a%@]+%*?)', i)
    if not start_pos then
      break
    end
    i = end_pos + 1
    if not bibliography_commands[command] then
      goto continue
    end
    local cursor = skip_optional_arguments(line, i)
    cursor = skip_whitespace(line, cursor)
    local value
    value, i = read_balanced_block(line, cursor)
    if value and #value > 0 then
      local resources = split_resources(value)
      for _, resource in ipairs(resources) do
        results[#results + 1] = resource
      end
    end
    ::continue::
  end
  return results
end

--- Find bibliography files in YAML front matter
--- @param lines string[] Buffer lines to search
--- @return string[] List of bibliography file paths
local function find_yaml_bibliography(lines)
  local resources = {}
  local in_front_matter = false
  local collecting_list = false
  for idx, line in ipairs(lines) do
    if idx == 1 and line:match('^%-%-%-%s*$') then
      in_front_matter = true
    elseif in_front_matter and line:match('^%-%-%-%s*$') then
      break
    elseif in_front_matter then
      local inline = line:match('^bibliography:%s*(.+)$')
      if inline then
        resources[#resources + 1] = trim(inline)
        collecting_list = false
      elseif line:match('^bibliography:%s*$') then
        collecting_list = true
      elseif line:match('^%S') and not line:match('^%s') then
        collecting_list = false
      end
      if collecting_list then
        local list_item = line:match('^%s*%-%s*(.+)%s*$')
        if list_item then
          resources[#resources + 1] = trim(list_item)
        end
      end
    end
  end
  return resources
end

--- Find Typst import statements
--- @param lines string[] Buffer lines to search
--- @return string[] List of imported file paths
local function find_typst_imports(lines)
  local imports = {}
  for _, line in ipairs(lines) do
    -- Match #import patterns with double quotes:
    -- #import "file.typ"
    -- #import "file.typ": item
    -- #import "file.typ": *
    -- Capture the path within double quotes
    for path in line:gmatch('#import%s+"([^"]+)"') do
      if path:match('%.typ$') then
        imports[#imports + 1] = trim(path)
      end
    end
    -- Match #import patterns with single quotes:
    -- #import 'file.typ'
    -- #import 'file.typ': item
    -- #import 'file.typ': *
    -- Capture the path within single quotes
    for path in line:gmatch("#import%s+'([^']+)'") do
      if path:match('%.typ$') then
        imports[#imports + 1] = trim(path)
      end
    end
  end
  return imports
end

--- Read lines from a file
--- @param filepath string The file path to read
--- @return string[]|nil List of lines or nil if file cannot be read
local function read_file_lines(filepath)
  local fd = io.open(filepath, 'r')
  if not fd then
    -- Silently return nil for missing imports - this is expected in many cases
    -- as users may import files that don't exist yet or are in different locations
    return nil
  end
  local lines = {}
  for line in fd:lines() do
    lines[#lines + 1] = line
  end
  fd:close()
  return lines
end

--- Find bibliography files in Typst #bibliography() declarations
--- Recursively follows #import statements to find bibliographies in imported files
--- @param lines string[] Buffer lines to search
--- @param base_dir string|nil Directory to resolve relative imports from
--- @param visited table<string, boolean>|nil Table to track visited files (prevents cycles)
--- @return string[] List of bibliography file paths
local function find_typst_bibliography(lines, base_dir, visited)
  visited = visited or {}
  local resources = {}

  -- Find direct bibliography declarations
  for _, line in ipairs(lines) do
    -- Match #bibliography("path/to/file.bib") with double quotes
    for path in line:gmatch('#bibliography%s*%(%s*"([^"]+)"%s*%)') do
      path = trim(path)
      if not path_util.is_absolute(path) and base_dir then
        path = path_util.joinpath(base_dir, path) --[[@as string]]
      end
      resources[#resources + 1] = path
    end
    -- Match #bibliography('path/to/file.bib') with single quotes
    for path in line:gmatch("#bibliography%s*%(%s*'([^']+)'%s*%)") do
      path = trim(path)
      if not path_util.is_absolute(path) and base_dir then
        path = path_util.joinpath(base_dir, path) --[[@as string]]
      end
      resources[#resources + 1] = path
    end
  end

  -- Follow imports to find bibliographies in imported files
  if base_dir then
    local imports = find_typst_imports(lines)
    for _, import_path in ipairs(imports) do
      local full_path
      if path_util.is_absolute(import_path) then
        full_path = path_util.normalize(import_path)
      else
        full_path = path_util.normalize(path_util.joinpath(base_dir, import_path))
      end

      if full_path and not visited[full_path] then
        visited[full_path] = true
        local import_lines = read_file_lines(full_path)
        if import_lines then
          local import_dir = vim.fs.dirname(full_path)
          local imported_resources = find_typst_bibliography(import_lines, import_dir, visited)
          for _, resource in ipairs(imported_resources) do
            -- Resolve imported resource paths relative to the imported file's directory
            if not path_util.is_absolute(resource) then
              resource = path_util.joinpath(import_dir, resource) --[[@as string]]
            end
            resources[#resources + 1] = resource
          end
        end
      end
    end
  end

  return resources
end

--- Find bibliography databases in GAPDoc <Bibliography Databases="..."/> declarations
--- Per the GAPDoc DTD the element is EMPTY with a required Databases attribute
--- and an optional Style attribute; several databases are separated by commas.
--- BibTeX databases are named without their .bib extension, while BibXMLext
--- databases carry their full .xml name and are skipped here, since this plugin
--- reads BibTeX and Hayagriva rather than BibXMLext.
--- The opening of a GAPDoc bibliography declaration
--- @type string
local BIBLIOGRAPHY_TAG = '<Bibliography'

--- Blank out the XML regions whose contents are not live markup
--- Comments, CDATA sections and processing instructions all hold text that an
--- XML processor never reads as markup, so a declaration inside one names a
--- bibliography that is not in use. An unterminated opener runs to the end of
--- the document, which is what an editor shows while such a region is being
--- typed. Regions are replaced by a space rather than removed so that the
--- markup around them cannot be glued together.
--- @param text string The document text
--- @return string The text with inactive regions blanked out
local function strip_inactive_regions(text)
  text = text:gsub('<!%-%-.-%-%->', ' ')
  text = text:gsub('<!%[CDATA%[.-%]%]>', ' ')
  text = text:gsub('<%?.-%?>', ' ')
  -- A DOCTYPE may carry an internal subset, whose entity declarations hold
  -- replacement text that is not markup until an entity is referenced. The
  -- '[^>%[]*' guard keeps this from reaching past the DOCTYPE's own '>' into a
  -- later element that happens to contain brackets.
  text = text:gsub('<!DOCTYPE[^>%[]*%[.-%]%s*>', ' ')
  text = text:gsub('<!DOCTYPE[^>]*>', ' ')
  text = text:gsub('<!%-%-.*$', ' ')
  text = text:gsub('<!%[CDATA%[.*$', ' ')
  text = text:gsub('<%?.*$', ' ')
  text = text:gsub('<!DOCTYPE.*$', ' ')
  return text
end

--- The character references XML predefines, which need no DTD declaration
--- @type table<string, string>
local xml_entities = {
  amp = '&',
  lt = '<',
  gt = '>',
  quot = '"',
  apos = "'",
}

--- Resolve one XML character reference to the character it stands for
--- @param reference string The reference body, without the '&' and ';'
--- @return string|nil The character, or nil when the reference is not resolvable
local function resolve_xml_reference(reference)
  local code = tonumber(reference:match('^#[xX](%x+)$') or '', 16) or tonumber(reference:match('^#(%d+)$') or '')
  if code then
    if code < 1 or code > 0x10FFFF then
      return nil
    end
    return vim.fn.nr2char(code, 1)
  end
  -- Entity names are case sensitive in XML, so they are looked up as written.
  return xml_entities[reference]
end

--- Decode the XML character references in an attribute value
--- An XML processor resolves these before GAPDoc ever sees the value, so this
--- runs before the value is split on commas. References that are not the five
--- predefined entities or a numeric escape are left as written.
--- @param value string The raw attribute value
--- @return string The decoded value
local function decode_xml_references(value)
  return (value:gsub('&(#?%w+);', resolve_xml_reference))
end

--- Read the Databases attribute of a single <Bibliography> element
--- @param element string The element text, from '<Bibliography' to its '>'
--- @return string|nil The attribute value, or nil when the element has none
local function read_databases_attribute(element)
  return element:match('Databases%s*=%s*"([^"]*)"') or element:match("Databases%s*=%s*'([^']*)'")
end

--- @param lines string[] Buffer lines to search
--- @return string[] File names as written in the Databases attribute with '.bib'
---   appended; entries may carry a directory part and may contain dots
local function find_gapdoc_bibliography(lines)
  -- Every buffer is scanned regardless of filetype, so the cost of joining the
  -- lines is only paid once a declaration can actually be present.
  local marked = false
  for _, line in ipairs(lines) do
    if line:find(BIBLIOGRAPHY_TAG, 1, true) then
      marked = true
      break
    end
  end
  if not marked then
    return {}
  end

  -- Joined so that a declaration split across lines is still found.
  local text = strip_inactive_regions(table.concat(lines, '\n'))

  local resources = {}
  -- One pass in source order, reading both attribute quote styles as they come,
  -- so that the returned list follows the document rather than the quoting.
  local cursor = 1
  while true do
    local start_pos = text:find(BIBLIOGRAPHY_TAG .. '%s', cursor)
    if not start_pos then
      break
    end
    local rest = text:sub(start_pos)
    -- Bounded by the element's own '>', so a Databases attribute belonging to a
    -- later element is never read. The second form covers an element still
    -- being typed at the end of the document, where no '>' exists yet.
    local element = rest:match('^<Bibliography%s[^>]*>') or rest:match('^<Bibliography%s[^>]*$')
    local databases = element and read_databases_attribute(element)
    databases = databases and decode_xml_references(databases)
    for _, name in ipairs(databases and split_resources(databases) or {}) do
      -- BibXMLext databases carry their full .xml name and are skipped; every
      -- other name is a BibTeX database, which the DTD defines as being
      -- written without its .bib extension, so it is always appended.
      if not name:lower():match('%.xml$') then
        resources[#resources + 1] = name .. '.bib'
      end
    end
    cursor = start_pos + #BIBLIOGRAPHY_TAG
  end
  return resources
end

--- Ensure a path has a bibliography extension (.bib, .yml, or .yaml)
--- @param path string|nil The path to check
--- @return string|nil The path with .bib extension if needed (unless it already has .yml or .yaml)
local function ensure_bib_extension(path)
  if not path or path == '' then
    return path
  end
  if path:find('[%*%?%[]') then
    return path
  end
  -- Accept .bib, .yml, .yaml extensions as-is
  if path:match('%.bib$') or path:match('%.ya?ml$') then
    return path
  end
  local filename = path:match('([^/\\]+)$') or path
  if filename:find('%.') then
    return path
  end
  return path .. '.bib'
end

--- Find the bibliographies a LaTeX buffer declares
--- @param ctx BibtexDiscoveryContext
--- @return string[]
function M.latex(ctx)
  local resources = {}
  for _, line in ipairs(ctx.lines) do
    for _, resource in ipairs(extract_command_paths(line)) do
      resources[#resources + 1] = resource
    end
  end
  return resources
end

--- Find the bibliographies declared in Markdown YAML front matter
--- @param ctx BibtexDiscoveryContext
--- @return string[]
function M.yaml(ctx)
  return find_yaml_bibliography(ctx.lines)
end

--- Find the bibliographies a Typst buffer declares, following its imports
--- @param ctx BibtexDiscoveryContext
--- @return string[]
function M.typst(ctx)
  return find_typst_bibliography(ctx.lines, ctx.dir)
end

--- Find the bibliographies a GAPDoc document declares
--- @param ctx BibtexDiscoveryContext
--- @return string[]
function M.gapdoc(ctx)
  return find_gapdoc_bibliography(ctx.lines)
end

--- Hooks shipped with the plugin, addressable by name from the configuration
--- @type table<string, BibtexDiscoveryFn>
M.builtin = {
  latex = M.latex,
  yaml = M.yaml,
  typst = M.typst,
  gapdoc = M.gapdoc,
}

--- The discovery shipped with the plugin, and the source of the config default
--- Every hook sits under '*' because buffer discovery is filetype agnostic: an
--- \addbibresource in a Markdown buffer is found today, and narrowing the hooks
--- per filetype would silently stop finding it. This is the opposite of
--- matchers.defaults, where the filetype decides which syntax applies.
--- The priorities reproduce the order the extractors ran in before they became
--- hooks.
--- @type table<string, table<string, table>>
M.defaults = {
  ['*'] = {
    latex = { priority = 10 },
    yaml = { priority = 20 },
    typst = { priority = 30 },
    -- Appends '.bib' itself, because GAPDoc names are extensionless by
    -- definition and the generic rule would misread a dotted name.
    gapdoc = { priority = 40, extension = false },
  },
}

--- The spec fields shipped for a built-in hook in a filetype context
--- @param name string The built-in hook name
--- @param filetype string|nil The filetype whose chain is being built
--- @return table|nil The shipped entry, or nil when nothing is shipped
local function shipped_spec(name, filetype)
  local per_filetype = filetype and M.defaults[filetype]
  local entry = per_filetype and per_filetype[name]
  if type(entry) ~= 'table' then
    entry = M.defaults['*'] and M.defaults['*'][name]
  end
  return type(entry) == 'table' and entry or nil
end

--- Describe the first unusable optional field of a configured spec table
--- @param spec table The user's spec table
--- @return string|nil A reason, or nil when every optional field is well formed
local function malformed_field_reason(spec)
  if spec.priority ~= nil and type(spec.priority) ~= 'number' then
    return string.format('priority is %s instead of a number', type(spec.priority))
  end
  if spec.extension ~= nil and type(spec.extension) ~= 'boolean' then
    return string.format('extension is %s instead of a boolean', type(spec.extension))
  end
  return nil
end

--- Normalize a configured discovery value into a spec
--- Accepts the same forms as a matcher: false or nil to disable, true for the
--- built-in of the same name, a built-in name, a function, or a spec table.
--- Invalid values are skipped with a single warning per name.
---
--- Whenever the hook comes from a built-in, the fields left out are inherited
--- in this order, so re-enabling one with true keeps what it ships with:
---   1. the field spelled out in the user's own spec table
---   2. the field this filetype ships for that built-in in M.defaults
---   3. the field '*' ships for that built-in in M.defaults
---   4. DEFAULT_PRIORITY for priority, nil for the rest
--- @param name string The configuration key the value was found under
--- @param value any The configured value
--- @param filetype string|nil The filetype whose chain is being built
--- @return BibtexDiscoverySpec|nil The normalized spec, or nil when disabled or invalid
function M.normalize(name, value, filetype)
  if value == nil or value == false then
    return nil
  end

  local find, extra, inherited
  if value == true then
    find = M.builtin[name]
    if not find then
      registry.warn_once(
        'discovery',
        name,
        string.format("discovery hook '%s' is enabled but no built-in hook has that name", name)
      )
      return nil
    end
    inherited = shipped_spec(name, filetype)
  elseif type(value) == 'function' then
    find = value
  elseif type(value) == 'string' then
    find = M.builtin[value]
    if not find then
      registry.warn_once(
        'discovery',
        name,
        string.format("discovery hook '%s' refers to unknown built-in hook '%s'", name, value)
      )
      return nil
    end
    inherited = shipped_spec(value, filetype)
  elseif type(value) == 'table' then
    local reason = malformed_field_reason(value)
    if reason then
      registry.warn_once('discovery', name, string.format("discovery hook '%s' is skipped: %s", name, reason))
      return nil
    end
    extra = value
    if type(value.find) == 'function' then
      find = value.find
    else
      find = M.builtin[name]
      if not find then
        registry.warn_once(
          'discovery',
          name,
          string.format("discovery hook '%s' has no find function and no built-in hook has that name", name)
        )
        return nil
      end
      inherited = shipped_spec(name, filetype)
    end
  else
    registry.warn_once(
      'discovery',
      name,
      string.format("discovery hook '%s' has unsupported type '%s'", name, type(value))
    )
    return nil
  end

  --- Read a spec field, preferring the user's own value over the shipped one
  --- @param field_name string The spec field to read
  --- @return any
  local function field(field_name)
    if extra and extra[field_name] ~= nil then
      return extra[field_name]
    end
    if inherited and inherited[field_name] ~= nil then
      return inherited[field_name]
    end
    return nil
  end

  return {
    name = name,
    find = find,
    priority = field('priority') or DEFAULT_PRIORITY,
    extension = field('extension'),
  }
end

--- Build the ordered hook chain for a filetype
--- Entries under the filetype key override same-named '*' entries.
---
--- Unlike matchers.chain, this falls back to the shipped defaults when no
--- discovery is configured at all. find_bib_files_from_buffer is public and is
--- called with no options, and buffer discovery has always worked in that case,
--- so an absent discovery key must not mean "discover nothing".
---
--- Turning discovery off is therefore explicit: `discovery = false`. An empty
--- table means the same thing, but only when the options reach this module
--- unmerged; setup() merges maps key by key, so an empty table configured there
--- keeps the shipped hooks. `false` is not a table and survives the merge.
--- @param filetype string|nil The buffer filetype
--- @param opts table|nil Configuration options
--- @return BibtexDiscoverySpec[] The hooks to run, in order
function M.chain(filetype, opts)
  local configured = opts and opts.discovery
  if configured == false then
    return {}
  end
  if configured ~= nil and configured ~= true and type(configured) ~= 'table' then
    -- Unusable: reported once, then treated as though nothing was configured,
    -- which for discovery means the shipped hooks.
    registry.warn_once('discovery', 'option', string.format('discovery is %s, which cannot be used', type(configured)))
    configured = nil
  end
  configured = (configured == true or configured == nil) and M.defaults or configured
  local shared = configured['*'] or {}
  local per_filetype = filetype and configured[filetype] or {}

  local values = {}
  for name, value in pairs(shared) do
    values[name] = value
  end
  for name, value in pairs(per_filetype) do
    values[name] = value
  end

  local specs = {}
  for name, value in pairs(values) do
    local spec = M.normalize(name, value, filetype)
    if spec then
      specs[#specs + 1] = spec
    end
  end

  table.sort(specs, function(a, b)
    if a.priority ~= b.priority then
      return a.priority < b.priority
    end
    return a.name < b.name
  end)
  return specs
end

--- Describe why a hook result is unusable, if it is
--- @param result any The value a hook returned
--- @return string|nil A reason, or nil when the result is well formed
local function malformed_result_reason(result)
  if type(result) == 'string' then
    return nil
  end
  if type(result) ~= 'table' then
    return string.format('returned %s instead of a list of file names', type(result))
  end
  for _, entry in ipairs(result) do
    if type(entry) ~= 'string' then
      return string.format('returned a list holding %s instead of a file name', type(entry))
    end
  end
  return nil
end

--- Run the hook chain and collect the file names it reports
--- Results are concatenated in chain order and left unresolved; the caller
--- resolves and deduplicates them.
--- @param ctx BibtexDiscoveryContext
--- @return string[] File names, in chain order
function M.collect(ctx)
  local resources = {}

  --- Record one reported name, applying the hook's extension rule
  --- @param spec BibtexDiscoverySpec The hook that reported it
  --- @param name string The file name reported
  local function remember(spec, name)
    resources[#resources + 1] = spec.extension == false and name or ensure_bib_extension(name)
  end

  for _, spec in ipairs(M.chain(ctx.filetype, ctx.opts)) do
    if not registry.has_failed(spec.find, ctx.filetype) then
      local ok, result = pcall(spec.find, ctx)
      local problem
      if not ok then
        problem = string.format('raised an error: %s', registry.describe_error(result))
      elseif result ~= nil and result ~= false then
        problem = malformed_result_reason(result)
      end
      if problem then
        registry.mark_failed(spec.find, ctx.filetype)
        registry.warn_once(
          'discovery',
          string.format('%s@%s', spec.name, ctx.filetype or registry.NO_FILETYPE),
          string.format(
            "discovery hook '%s' %s and is disabled for filetype '%s'",
            spec.name,
            problem,
            ctx.filetype or 'unset'
          )
        )
      elseif type(result) == 'string' then
        remember(spec, result)
      elseif result then
        for _, name in ipairs(result) do
          remember(spec, name)
        end
      end
    end
  end
  return resources
end

--- Internal helpers exposed for testing. Not part of the public API.
M.__test = {
  --- Forget the per-session warning and failed-hook state.
  reset = registry.reset,
}

return M
