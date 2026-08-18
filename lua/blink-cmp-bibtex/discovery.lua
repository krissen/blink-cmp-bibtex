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
--- @field root string|nil The project root, from the root_markers option, or
---   the buffer's directory when no marker is found
--- @field opts table Configuration options

--- One bibliography a hook reports, with where it was declared
--- A hook may report a bare file name instead, which carries no position.
--- @class BibtexDiscoveryResult
--- @field name string The file name as declared
--- @field line integer|nil The line the declaration was found on, 1-based
--- @field file string|nil The declaring file, when it is not the buffer itself

--- One bibliography as collected, with the hook that reported it
--- @class BibtexDiscoveryEntry
--- @field name string The file name, with the hook's extension rule applied
--- @field hook string The name of the hook that reported it
--- @field line integer|nil The line the declaration was found on, 1-based
--- @field file string|nil The declaring file, when it is not the buffer itself

--- A discovery hook
--- Unlike a matcher, a hook takes no subject argument: the lines it reads are
--- already part of the context. Each reported bibliography is either a bare
--- file name or a record naming it, which lets a hook say where the
--- declaration was found.
--- @alias BibtexDiscoveryReport string|BibtexDiscoveryResult
--- @alias BibtexDiscoveryFn fun(ctx: BibtexDiscoveryContext): BibtexDiscoveryReport[]|BibtexDiscoveryReport|nil

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
--- @return BibtexDiscoveryResult[] List of bibliography file paths, with the
---   line each was declared on
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
        resources[#resources + 1] = { name = trim(inline), line = idx }
        collecting_list = false
      elseif line:match('^bibliography:%s*$') then
        collecting_list = true
      elseif line:match('^%S') and not line:match('^%s') then
        collecting_list = false
      end
      if collecting_list then
        local list_item = line:match('^%s*%-%s*(.+)%s*$')
        if list_item then
          resources[#resources + 1] = { name = trim(list_item), line = idx }
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
--- @return BibtexDiscoveryResult[] List of bibliography file paths, with the
---   line each was declared on and, for a declaration reached through an
---   import, the file declaring it
local function find_typst_bibliography(lines, base_dir, visited)
  visited = visited or {}
  local resources = {}

  -- Find direct bibliography declarations
  for idx, line in ipairs(lines) do
    -- Match #bibliography("path/to/file.bib") with double quotes, then the
    -- single-quoted form, so that the results follow the source order.
    for _, pattern in ipairs({ '#bibliography%s*%(%s*"([^"]+)"%s*%)', "#bibliography%s*%(%s*'([^']+)'%s*%)" }) do
      for path in line:gmatch(pattern) do
        path = trim(path)
        if not path_util.is_absolute(path) and base_dir then
          path = path_util.joinpath(base_dir, path) --[[@as string]]
        end
        resources[#resources + 1] = { name = path, line = idx }
      end
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
            if not path_util.is_absolute(resource.name) then
              resource.name = path_util.joinpath(import_dir, resource.name) --[[@as string]]
            end
            -- A declaration reached through several imports keeps the file it
            -- was written in, which the innermost call already recorded.
            resource.file = resource.file or full_path
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
    return vim.fn.nr2char(code, true)
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

--- Read every <Bibliography> declaration in an XML document
--- The caller has already established that the document can hold one; this is
--- the part that is worth the joins and the pattern work.
--- @param lines string[] The document lines
--- @return string[] File names as written in the Databases attribute with
---   '.bib' appended; entries may carry a directory part and may contain dots
local function extract_gapdoc_databases(lines)
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

--- Whether a document can hold a bibliography declaration at all
--- Every buffer is scanned regardless of filetype, so the cost of joining the
--- lines is only paid once a declaration can actually be present.
--- @param lines string[] The document lines
--- @return boolean
local function has_bibliography_marker(lines)
  for _, line in ipairs(lines) do
    if line:find(BIBLIOGRAPHY_TAG, 1, true) then
      return true
    end
  end
  return false
end

--- @param lines string[] Buffer lines to search
--- @return string[] File names as written in the Databases attribute with '.bib'
---   appended; entries may carry a directory part and may contain dots
local function find_gapdoc_bibliography(lines)
  if not has_bibliography_marker(lines) then
    return {}
  end
  return extract_gapdoc_databases(lines)
end

--- Size caps for the files the GAP package hook reads, in bytes
--- A package's GAP files and its manual XML are small; anything larger is a
--- generated artifact that would cost more to read than it can be worth.
--- Overridable through M.__test so the caps can be exercised cheaply.
--- @type table<string, number>
local gap_size_caps = {
  gap = 64 * 1024,
  xml = 1024 * 1024,
}

--- The limits of the GAP package hook, writable through M.__test for testing
--- @type table<string, number>
local gap_limits = {
  --- How many XML files a documentation directory is read from
  max_xml_files = 50,
}

--- The main XML file names AutoDoc and GAPDoc packages use, in preference order
--- @type string[]
local GAP_MAIN_XML = { '_main.xml', 'main.xml', 'manual.xml' }

--- What has been found for a package root, keyed by that root
--- @type table<string, table>
local gap_package_cache = {}

--- Stat a path without ever raising
--- @param path string|nil The path to stat
--- @return table|nil The stat table, or nil when the path cannot be stat'ed
local function safe_stat(path)
  if not path or path == '' then
    return nil
  end
  local uv = vim.uv or vim.loop
  local ok, stat = pcall(uv.fs_stat, path)
  if not ok then
    return nil
  end
  return stat
end

--- Take a change stamp of a path
--- Absence is a stamp of its own, so that a makedoc.g appearing later, or a
--- documentation directory being created, invalidates what was cached.
--- @param path string The path to stamp
--- @return table|false The stamp, or false when the path does not exist
local function stamp_path(path)
  local stat = safe_stat(path)
  if not stat then
    return false
  end
  return {
    sec = stat.mtime and stat.mtime.sec or 0,
    nsec = stat.mtime and stat.mtime.nsec or 0,
    size = stat.size or 0,
  }
end

--- Whether two stamps describe the same state
--- @param a table|false|nil
--- @param b table|false|nil
--- @return boolean
local function same_stamp(a, b)
  if not a or not b then
    return not a and not b
  end
  return a.sec == b.sec and a.nsec == b.nsec and a.size == b.size
end

--- Read a file that is small enough to be worth reading
--- @param path string The file to read
--- @param cap number The largest size accepted, in bytes
--- @return string[]|nil The lines, or nil when the file is missing or too large
local function read_capped_file(path, cap)
  local stat = safe_stat(path)
  if not stat or stat.type == 'directory' or (stat.size or 0) > cap then
    return nil
  end
  local ok, lines = pcall(read_file_lines, path)
  if not ok then
    return nil
  end
  return lines
end

--- Read a GAP record field written as a string literal
--- Comments are stripped first, since a '#' starts one for the rest of the line.
--- @param lines string[] The file lines
--- @param field string The field name
--- @return string|nil The first value found
local function read_gap_field(lines, field)
  local pattern = '%f[%w_]' .. field .. '%s*:=%s*"([^"]+)"'
  for _, line in ipairs(lines) do
    local code = line:gsub('#.*$', '')
    local value = code:match(pattern)
    if value then
      return value
    end
  end
  return nil
end

--- List the XML files of a documentation directory, in preference order
--- The main manual comes first under the names AutoDoc and GAPDoc generate,
--- then the file named after the package, then everything else alphabetically.
--- @param doc_dir string The documentation directory
--- @param pkg_name string|nil The package name from PackageInfo.g
--- @return string[] File names, without their directory part
local function list_gap_xml_files(doc_dir, pkg_name)
  local names = {}
  -- The whole directory is listed before anything is ranked: reading a
  -- directory entry is cheap, and capping the walk instead would let the
  -- manual itself be the file dropped in a directory of generated chapters.
  local ok = pcall(function()
    for name, entry_type in vim.fs.dir(doc_dir) do
      if entry_type ~= 'directory' and name:lower():match('%.xml$') then
        names[#names + 1] = name
      end
    end
  end)
  if not ok then
    return {}
  end

  local preferred = {}
  for index, name in ipairs(GAP_MAIN_XML) do
    preferred[name] = index
  end
  if pkg_name then
    preferred[pkg_name .. '.xml'] = #GAP_MAIN_XML + 1
  end
  local last = #GAP_MAIN_XML + 2

  table.sort(names, function(a, b)
    local rank_a = preferred[a] or last
    local rank_b = preferred[b] or last
    if rank_a ~= rank_b then
      return rank_a < rank_b
    end
    return a < b
  end)

  -- Only now, with the manual at the front, is the list cut to what is read.
  for index = #names, gap_limits.max_xml_files + 1, -1 do
    names[index] = nil
  end
  return names
end

--- Find the bibliographies of the GAP package a buffer belongs to
--- The declaration is rarely in the file being edited: GAPDoc keeps it in the
--- package's main XML, which AutoDoc generates, and which may not exist at all
--- in a fresh checkout. Both the manual and AutoDoc's naming convention are
--- therefore read from the package itself rather than from the buffer.
--- @param ctx BibtexDiscoveryContext
--- @param pkg_root string The package root, the directory holding PackageInfo.g
--- @param info_path string The path to PackageInfo.g
--- @return BibtexDiscoveryResult[] Absolute bibliography paths, with the manual
---   that declared them when one did
--- @return table<string, table|false> The stamps the result depends on
local function collect_gap_package_bibliography(ctx, pkg_root, info_path)
  local stamps = {}

  --- Stamp a path the result depends on
  --- @param path string
  local function depends_on(path)
    stamps[path] = stamp_path(path)
  end

  depends_on(info_path)
  local info_lines = read_capped_file(info_path, gap_size_caps.gap)
  local pkg_name = info_lines and read_gap_field(info_lines, 'PackageName') or nil

  local makedoc_path = path_util.joinpath(pkg_root, 'makedoc.g') --[[@as string]]
  depends_on(makedoc_path)
  local makedoc_lines = read_capped_file(makedoc_path, gap_size_caps.gap)
  local doc_rel = makedoc_lines and read_gap_field(makedoc_lines, 'dir') or nil
  local bib_name = makedoc_lines and read_gap_field(makedoc_lines, 'bib') or nil

  doc_rel = doc_rel and doc_rel ~= '' and doc_rel or 'doc'
  local doc_dir = path_util.is_absolute(doc_rel) and doc_rel or path_util.joinpath(pkg_root, doc_rel) --[[@as string]]

  local results = {}
  local seen = {}

  --- Record one absolute path, keeping the first occurrence
  --- @param path string|nil
  --- @param declared_in string|nil The manual that declared it, if one did
  local function remember(path, declared_in)
    if path and path ~= '' and not seen[path] then
      seen[path] = true
      results[#results + 1] = { name = path, file = declared_in }
    end
  end

  -- The manual's own declaration, which names the databases in use.
  depends_on(doc_dir)
  local bufname = ctx.bufname and ctx.bufname ~= '' and path_util.normalize(ctx.bufname) or nil
  for _, name in ipairs(list_gap_xml_files(doc_dir, pkg_name)) do
    local xml_path = path_util.joinpath(doc_dir, name) --[[@as string]]
    depends_on(xml_path)
    -- The buffer itself was already offered to the gapdoc hook, and what is on
    -- disk for it may be older than what is being edited.
    if not bufname or path_util.normalize(xml_path) ~= bufname then
      local lines = read_capped_file(xml_path, gap_size_caps.xml)
      if lines and has_bibliography_marker(lines) then
        local databases = extract_gapdoc_databases(lines)
        if #databases > 0 then
          for _, database in ipairs(databases) do
            -- The line is not reported: the databases are read from the
            -- document as one joined text, which no longer knows the lines.
            remember(path_util.joinpath(vim.fs.dirname(xml_path), database), xml_path)
          end
          break
        end
      end
    end
  end

  -- AutoDoc's convention, which holds before the manual has ever been built.
  -- A manual that declares its databases has said which ones are in use, so
  -- the convention is only consulted when it declared none.
  if #results == 0 then
    local convention = bib_name and bib_name:gsub('%.bib$', '') or pkg_name
    if bib_name and bib_name:lower():match('%.xml$') then
      -- A BibXMLext database, which this plugin does not read.
      convention = pkg_name
    end
    if convention and convention ~= '' then
      remember(path_util.joinpath(doc_dir, convention .. '.bib'))
    end
  end

  return results, stamps
end

--- Whether a cache entry still describes the file system
--- @param entry table The cache entry
--- @return boolean
local function gap_cache_is_current(entry)
  for path, stamp in pairs(entry.stamps) do
    if not same_stamp(stamp, stamp_path(path)) then
      return false
    end
  end
  return true
end

--- @param ctx BibtexDiscoveryContext
--- @return BibtexDiscoveryResult[] Absolute bibliography paths
local function find_gap_package_bibliography(ctx)
  if not ctx.dir or ctx.dir == '' then
    return {}
  end
  -- A buffer that declares a database of its own is the gapdoc hook's business.
  -- The bare marker is not enough to defer on: a declaration inside a comment
  -- or a CDATA section, or one whose Databases attribute is empty, gives the
  -- gapdoc hook nothing either, and deferring to it would leave the buffer
  -- without any bibliography at all.
  if #find_gapdoc_bibliography(ctx.lines or {}) > 0 then
    return {}
  end

  local ok, found = pcall(vim.fs.find, { 'PackageInfo.g' }, { upward = true, path = ctx.dir, limit = 1 })
  local info_path = ok and found and found[1] or nil
  if not info_path then
    return {}
  end
  local pkg_root = vim.fs.dirname(info_path)

  local bufname = ctx.bufname or ''
  local cached = gap_package_cache[pkg_root]
  if cached and cached.bufname == bufname and gap_cache_is_current(cached) then
    return vim.list_extend({}, cached.result)
  end

  local result, stamps = collect_gap_package_bibliography(ctx, pkg_root, info_path)
  gap_package_cache[pkg_root] = { bufname = bufname, stamps = stamps, result = result }
  return vim.list_extend({}, result)
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
--- @return BibtexDiscoveryResult[]
function M.latex(ctx)
  local resources = {}
  for idx, line in ipairs(ctx.lines) do
    for _, resource in ipairs(extract_command_paths(line)) do
      resources[#resources + 1] = { name = resource, line = idx }
    end
  end
  return resources
end

--- Find the bibliographies declared in Markdown YAML front matter
--- @param ctx BibtexDiscoveryContext
--- @return BibtexDiscoveryResult[]
function M.yaml(ctx)
  return find_yaml_bibliography(ctx.lines)
end

--- Find the bibliographies a Typst buffer declares, following its imports
--- @param ctx BibtexDiscoveryContext
--- @return BibtexDiscoveryResult[]
function M.typst(ctx)
  return find_typst_bibliography(ctx.lines, ctx.dir)
end

--- Find the bibliographies a GAPDoc document declares
--- @param ctx BibtexDiscoveryContext
--- @return string[]
function M.gapdoc(ctx)
  return find_gapdoc_bibliography(ctx.lines)
end

--- Find the bibliographies of the GAP package the buffer belongs to
--- Unlike the other hooks this one reads the package around the buffer rather
--- than the buffer itself, and returns absolute paths. A path a manual declared
--- carries that manual as its declaring file; one derived from AutoDoc's naming
--- convention was never declared anywhere and carries none.
--- @param ctx BibtexDiscoveryContext
--- @return BibtexDiscoveryResult[]
function M.gap_package(ctx)
  return find_gap_package_bibliography(ctx)
end

--- Hooks shipped with the plugin, addressable by name from the configuration
--- @type table<string, BibtexDiscoveryFn>
M.builtin = {
  latex = M.latex,
  yaml = M.yaml,
  typst = M.typst,
  gapdoc = M.gapdoc,
  gap_package = M.gap_package,
}

--- The discovery shipped with the plugin, and the source of the config default
--- Every hook that reads the buffer sits under '*' because buffer discovery is
--- filetype agnostic: an \addbibresource in a Markdown buffer is found today,
--- and narrowing those hooks per filetype would silently stop finding it. A
--- hook that probes the file system instead is narrowed to the filetypes where
--- it can pay off, so that the other buffers never pay for it. This is still
--- looser than matchers.defaults, where the filetype decides which syntax
--- applies.
--- The priorities of the '*' hooks reproduce the order the extractors ran in
--- before they became hooks.
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
  -- The GAP package hook runs after gapdoc, so that a declaration in the
  -- buffer wins over the one the package's manual makes. It returns absolute
  -- paths and appends '.bib' itself.
  gap = { gap_package = { priority = 45, extension = false } },
  xml = { gap_package = { priority = 45, extension = false } },
  autodoc = { gap_package = { priority = 45, extension = false } },
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
  if configured == nil or configured == true then
    configured = M.defaults
  end
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
--- A reported bibliography is either a bare file name or a record naming it,
--- so a table entry is well formed exactly when its name is a string.
--- @param result any The value a hook returned
--- @return string|nil A reason, or nil when the result is well formed
local function malformed_result_reason(result)
  if type(result) == 'string' then
    return nil
  end
  if type(result) ~= 'table' then
    return string.format('returned %s instead of a list of file names', type(result))
  end
  if type(result.name) == 'string' then
    return nil
  end
  for _, entry in ipairs(result) do
    if type(entry) == 'table' then
      if type(entry.name) ~= 'string' then
        return string.format('returned a list holding a record naming %s instead of a file name', type(entry.name))
      end
    elseif type(entry) ~= 'string' then
      return string.format('returned a list holding %s instead of a file name', type(entry))
    end
  end
  return nil
end

--- Run the hook chain and collect the bibliographies it reports, with origins
--- Results are concatenated in chain order and left unresolved; the caller
--- resolves and deduplicates them.
--- @param ctx BibtexDiscoveryContext
--- @return BibtexDiscoveryEntry[] Reported bibliographies, in chain order
function M.collect_detailed(ctx)
  --- @type BibtexDiscoveryEntry[]
  local resources = {}

  --- Record one reported bibliography, applying the hook's extension rule
  --- @param spec BibtexDiscoverySpec The hook that reported it
  --- @param report BibtexDiscoveryReport The bibliography reported
  local function remember(spec, report)
    local record = type(report) == 'table' and report or { name = report }
    resources[#resources + 1] = {
      name = spec.extension == false and record.name or ensure_bib_extension(record.name) --[[@as string]],
      hook = spec.name,
      line = record.line,
      file = record.file,
    }
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
      elseif type(result) == 'string' or (type(result) == 'table' and type(result.name) == 'string') then
        remember(spec, result)
      elseif result then
        for _, report in ipairs(result) do
          remember(spec, report)
        end
      end
    end
  end
  return resources
end

--- Run the hook chain and collect the file names it reports
--- The names collect_detailed reports, in the same order; the origins are
--- dropped, which is all a caller that only resolves paths needs.
--- @param ctx BibtexDiscoveryContext
--- @return string[] File names, in chain order
function M.collect(ctx)
  local names = {}
  for _, entry in ipairs(M.collect_detailed(ctx)) do
    names[#names + 1] = entry.name
  end
  return names
end

--- Internal helpers exposed for testing. Not part of the public API.
M.__test = {
  --- Forget the per-session warning and failed-hook state, and what the GAP
  --- package hook has cached.
  reset = function()
    gap_package_cache = {}
    registry.reset()
  end,
  --- The size caps of the GAP package hook, in bytes, writable for testing.
  gap_size_caps = gap_size_caps,
  --- The limits of the GAP package hook, writable for testing.
  gap_limits = gap_limits,
}

return M
