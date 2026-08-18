# API Documentation

This document provides detailed API documentation for `blink-cmp-bibtex` modules.

## Module: blink-cmp-bibtex

Main entry point for the BibTeX completion source.

### `Source.new(opts)`

Create a new source instance.

**Parameters:**
- `opts` (table, optional): Configuration overrides

**Returns:**
- `Source`: A new source instance

**Example:**
```lua
local source = require('blink-cmp-bibtex').new({
  filetypes = { "tex", "markdown" }
})
```

### `Source:enabled()`

Whether the source is active in the current buffer.

**Returns:**
- `boolean`: True when `opts.filetypes` is empty, or contains the current
  buffer's filetype

blink.cmp collects trigger characters only from enabled providers, which is what
keeps matcher trigger characters scoped to their filetypes.

### `Source:get_trigger_characters()`

Characters that should open the completion menu in the current buffer.

**Returns:**
- `string[]`: The deduplicated `trigger_characters` declared by the matcher
  chain for the current buffer's filetype

### `Source:get_completions(context, callback)`

Get completion items for the current context.

**Parameters:**
- `context` (table): Completion context from blink.cmp containing:
  - `bufnr` (number): Buffer number
  - `line` (string): Current line text
  - `cursor` (table): Cursor position
- `callback` (function): Callback to invoke with completion results

**Returns:**
- `function`: Cancellation function that can be called to abort the completion

**Example:**
```lua
source:get_completions(context, function(response)
  -- Handle completion items
  for _, item in ipairs(response.items) do
    print(item.label)
  end
end)
```

### `Source:resolve(item, callback)`

Resolve additional details for a completion item. Currently returns the item unchanged.

**Parameters:**
- `item` (table): The completion item to resolve
- `callback` (function): Callback to invoke with resolved item

### `Source:execute(context, item, callback, default_implementation)`

Execute after a completion item is accepted. Used for auto_add functionality to copy global entries to local bib.

**Parameters:**
- `context` (table): Completion context from blink.cmp
- `item` (table): The accepted completion item
- `callback` (function): Callback to invoke when done
- `default_implementation` (function): Default execute implementation

**Behavior:**
- Runs the default implementation first (if provided)
- If `local_bib.auto_add` is enabled and the accepted entry is from a global file, copies it to the local bib target

### `Source.copy_to_local_bib(key)`

Manually copy a BibTeX entry to the local bib file.

**Parameters:**
- `key` (string, optional): The citation key to copy. If nil, tries to detect from cursor position.

**Returns:**
- `boolean`: True if entry was copied successfully

**Example:**
```lua
-- Copy a specific key
require('blink-cmp-bibtex').copy_to_local_bib('Smith2023')

-- Copy entry at cursor (detects key from @key, {key, or ,key patterns)
require('blink-cmp-bibtex').copy_to_local_bib()
```

**Vim Command:**
```vim
:BibTeXCopyToLocal [key]
```

### `Source.setup(opts)`

Configure global default settings.

**Parameters:**
- `opts` (table, optional): Configuration options
  - `filetypes` (string[]): Supported filetypes (default: `{"tex", "plaintex", "markdown", "rmd", "typst"}`)
  - `files` (string[]): List of local BibTeX file paths to always include
  - `global_files` (string[]): List of global (shared) BibTeX file paths
  - `search_paths` (string[]): Glob patterns or paths to search for BibTeX files
  - `root_markers` (string[]): Files/directories indicating project root (default: `{".git", "latexmkrc", "texmf.cnf"}`)
  - `citation_commands` (string[]): LaTeX citation commands to recognize
  - `matchers` (table): Citation matchers per filetype, keyed by filetype with
    `'*'` applying everywhere (see
    [Module: blink-cmp-bibtex.matchers](#module-blink-cmp-bibtexmatchers))
  - `preview_style` (string): Preview template name (`"apa"` or `"ieee"`, default: `"apa"`)
  - `source_indicator` (boolean): Show source indicators when mixing local and global files (default: `true`)
  - `max_entries` (number): Maximum entries to collect (default: 4000)
  - `local_bib` (table): Local bibliography management options
    - `enabled` (boolean): Enable local bibliography management (default: `false`)
    - `target` (string): Path to local bib file, relative to project root
    - `targets` (table): Per-directory targets: `{ ["/path/to/project"] = "refs.bib" }`
    - `patterns` (string[]): Fallback patterns to search (default: `{ "local.bib", "references.bib" }`)
    - `auto_add` (boolean): Automatically copy global entries on accept (default: `false`)
    - `create_if_missing` (boolean): Create target file if it doesn't exist (default: `false`)
    - `notify_on_add` (boolean): Show notification when entry is added (default: `true`)
    - `notify_on_duplicate` (boolean): Show notification for duplicate entries (default: `false`)
    - `duplicate_check` (boolean): Check for existing entries before adding (default: `true`)

**Example:**
```lua
require('blink-cmp-bibtex').setup({
  filetypes = { "tex", "markdown" },
  files = { "references.bib" },
  global_files = { vim.fn.expand("~/research/master.bib") },
  preview_style = "ieee",
  source_indicator = true,
  search_paths = { "bib/*.bib" }
})
```

## Module: blink-cmp-bibtex.config

Configuration management for blink-cmp-bibtex.

### `config.setup(opts)`

Setup configuration with custom options.

**Parameters:**
- `opts` (table, optional): User-provided configuration options

**Returns:**
- `table`: The final merged configuration

### `config.extend(opts)`

Extend current options with additional overrides.

**Parameters:**
- `opts` (table, optional): Additional options to merge

**Returns:**
- `table`: The extended configuration

### `config.get()`

Get the current configuration.

**Returns:**
- `table`: Current configuration options

### `config.defaults()`

Get the default configuration.

**Returns:**
- `table`: Default configuration options

### Merge semantics

`setup()` and `extend()` merge user options into the defaults key by key, with
one exception: list-like tables are replaced wholesale rather than merged by
index. Configuring `citation_commands`, `filetypes`, `files`, `global_files`,
`search_paths` or `root_markers` therefore discards the built-in list instead of
producing a mixture of both. Keyed maps such as `local_bib` and `matchers` are
merged, so an empty table leaves the nested defaults intact.

## Module: blink-cmp-bibtex.matchers

Citation matchers decide whether the cursor sits inside a citation and which key
prefix has been typed. The module never requires `config`; it only receives
options.

### Types

**`BibtexMatchResult`** — returned by a matcher on a match:

- `prefix` (string): The citation key prefix typed so far
- `trigger` (string|nil): Name of the syntax that matched
- `command` (string|nil): The citation command that matched, when applicable
- `sanitize` (boolean|nil): Override prefix sanitization for this match

**`BibtexMatcherFn`** — `fun(text: string, opts: table, ctx: table|nil): BibtexMatchResult|nil`.
`text` is the line up to the cursor, `opts` the resolved configuration, and
`ctx` a table with `bufnr`, `filetype`, `line` and `col`.

**`BibtexMatcherSpec`** — a normalized matcher entry:

- `name` (string): The matcher name
- `match` (BibtexMatcherFn): The matching function
- `priority` (number): Lower runs first (default `50`)
- `sanitize` (boolean|nil): Whether matched prefixes are sanitized
- `trigger_characters` (string[]|nil): Characters that should open the menu

### `matchers.latex(text, opts)`

Match LaTeX citation commands, including optional arguments
(`\parencite[see][p. 42]{key`) and starred variants. Only commands listed in
`opts.citation_commands` match.

**Returns:**
- `BibtexMatchResult|nil`: `{ prefix, command, trigger = 'latex' }`, or nil

### `matchers.pandoc(text)`

Match Pandoc citation syntax: `[@key`, `@key` at a word boundary, and `@key` at
the start of the line.

**Returns:**
- `BibtexMatchResult|nil`: `{ prefix, trigger = 'pandoc' }`, or nil

### `matchers.typst(text)`

Match Typst citation syntax: `@key` (also directly after a word character) and
`#cite(<key`.

**Returns:**
- `BibtexMatchResult|nil`: `{ prefix, trigger = 'typst' }`, or nil

### `matchers.gapdoc(text)`

Match GAPDoc's `<Cite Key="key` (single quotes accepted). GAPDoc keys are used
verbatim, so the result opts out of prefix sanitization.

**Returns:**
- `BibtexMatchResult|nil`: `{ prefix, trigger = 'gapdoc', sanitize = false }`, or nil

### `matchers.builtin`

Table mapping the built-in names `latex`, `pandoc`, `typst` and `gapdoc` to
their matcher functions. Configuration values may refer to these by name.

### `matchers.defaults`

The per-filetype dispatch shipped with the plugin, keyed by filetype with `'*'`
applying everywhere. It is the source of the `matchers` configuration default
(`config.lua` deep-copies it) and the source of the inherited spec fields in
`normalize`. It lives here rather than in `config.lua` so that the two modules
do not depend on each other.

### `matchers.normalize(name, value, filetype)`

Normalize a configured matcher value into a spec.

**Parameters:**
- `name` (string): The configuration key the value was found under
- `value` (any): `false`/`nil` (disabled), `true` (built-in of the same name), a
  string (named built-in), a function, or a spec table
- `filetype` (string|nil): The filetype whose chain is being built, used to
  resolve inherited spec fields

**Returns:**
- `BibtexMatcherSpec|nil`: The normalized spec, or nil when disabled or invalid

When the match function comes from a built-in, `priority`, `sanitize` and
`trigger_characters` are resolved in this order:

1. the field spelled out in the user's own spec table
2. the field this filetype ships for that built-in in `matchers.defaults`
3. the field `'*'` ships for that built-in in `matchers.defaults`
4. `50` for `priority`, `nil` for the rest

This is what lets `gapdoc = true` in an `xml` buffer keep the shipped priority
and trigger character. Invalid values are reported once per name through
`vim.notify` and skipped.

### `matchers.chain(filetype, opts)`

Build the ordered matcher chain for a filetype. Entries under the filetype key
override same-named entries under `'*'`.

**Parameters:**
- `filetype` (string|nil): The buffer filetype
- `opts` (table): Configuration options

**Returns:**
- `BibtexMatcherSpec[]`: The matchers to run, sorted by priority then name

### `matchers.detect(text, opts, ctx)`

Run the matcher chain against the text before the cursor and return the first
match.

**Parameters:**
- `text` (string): The text up to the cursor
- `opts` (table): Configuration options
- `ctx` (table|nil): Context with `bufnr`, `filetype`, `line` and `col`

**Returns:**
- `BibtexMatchResult|nil`: The first match, or nil
- `BibtexMatcherSpec|nil`: The matcher that produced the result

Matchers are called through `pcall`. A matcher that raises is reported once and
disabled for the rest of the session.

### `matchers.trigger_characters(filetype, opts)`

Collect the trigger characters declared by a filetype's matcher chain.

**Parameters:**
- `filetype` (string|nil): The buffer filetype
- `opts` (table): Configuration options

**Returns:**
- `string[]`: Deduplicated trigger characters

**Example:**
```lua
local matchers = require('blink-cmp-bibtex.matchers')

require('blink-cmp-bibtex').setup({
  filetypes = { 'tex', 'markdown', 'xml' },
  matchers = {
    xml = {
      refkey = {
        priority = 5,
        sanitize = false,
        trigger_characters = { '"' },
        match = function(text)
          local prefix = text:match('<Ref%s+[^>]-BibKey%s*=%s*"([^"]*)$')
          if prefix then
            return { prefix = prefix, trigger = 'refkey' }
          end
        end,
      },
    },
  },
})
```

## Module: blink-cmp-bibtex.health

Health check registered for `:checkhealth blink-cmp-bibtex`.

### `health.check()`

Report the resolved configuration and flag matcher setups that can never fire.

The report describes the buffer the check was run from. `:checkhealth` renders
in a buffer of its own, so the alternate buffer is used when the current one is
the report itself.

**Reports:**
- `filetypes`, `preview_style`, `max_entries` and the number of configured
  `files`, `global_files`, `search_paths` and `root_markers`
- A `bibliographies` section listing every path `scan.resolve_bib_sources`
  resolves for that buffer, annotated with its origins: global files first,
  then local ones, then the paths that are not there. How the last are worded
  follows their origins — an option's path is warned about by the option it was
  configured in and a directory is warned about as one, a path the buffer
  declared is warned about with the position of the declaration, and one nobody
  declared (a GAP package's conventional name, a
  `local_bib.target` created on the first copy) is reported as not present yet
- A warning when the buffer's filetype is not in `filetypes`, since the source
  is not offered there
- The matcher chain for `'*'` and for each configured filetype, with priorities
- A warning when a filetype has matchers configured but is missing from
  `filetypes`; matchers shipped with the plugin that are dormant for this reason
  are reported as information instead
- A warning when no matchers are configured at all

## Module: blink-cmp-bibtex.cache

Cache management for parsed BibTeX entries.

### `cache.collect(paths, limit)`

Collect all entries from multiple BibTeX files.

**Parameters:**
- `paths` (string[]): List of file paths to collect from
- `limit` (number, optional): Maximum number of entries to collect

**Returns:**
- `table[]`: List of all collected entries, each containing:
  - `key` (string): Citation key
  - `entrytype` (string): Entry type (e.g., "article", "book")
  - `fields` (table): Field values
  - `source_path` (string): Path to source file
  - `raw` (string): Raw BibTeX entry text

### `cache.invalidate(path)`

Invalidate cache for a specific file path.

**Parameters:**
- `path` (string): The file path to invalidate

## Module: blink-cmp-bibtex.parser

BibTeX file parser.

### `parser.parse(content)`

Parse BibTeX content into a list of entries.

**Parameters:**
- `content` (string): The BibTeX file content

**Returns:**
- `table[]`: List of parsed entries, each containing:
  - `key` (string): Citation key
  - `entrytype` (string): Entry type
  - `fields` (table): Parsed fields with LaTeX commands stripped

**Example:**
```lua
local parser = require('blink-cmp-bibtex.parser')
local entries = parser.parse([[
@article{key2023,
  author = {Doe, John},
  title = {Example Article},
  year = {2023}
}
]])
```

### `parser.parse_file(path)`

Parse a BibTeX file and return all entries.

**Parameters:**
- `path` (string): The file path to parse

**Returns:**
- `table[]`: List of parsed entries

**Errors:**
- Throws an error if the file cannot be opened

## Module: blink-cmp-bibtex.discovery

Bibliography discovery from the current buffer. A *hook* reads the buffer and
reports the files it declares; the hooks that run in a filetype are configured
through the `discovery` option, whose default is `discovery.defaults`.

### `discovery.latex(ctx)` / `discovery.yaml(ctx)` / `discovery.typst(ctx)` / `discovery.gapdoc(ctx)`

The buffer-reading hooks shipped with the plugin, reading `\addbibresource{}` and friends,
Markdown YAML front matter, Typst `#bibliography()` (following `#import`), and
GAPDoc `<Bibliography Databases="…"/>` respectively.

These return plain file names, and will keep doing so: they are public, and a
user hook that wraps one passes its result straight through. The health report
still shows the line each declaration was found on — `collect_detailed`
recognizes a shipped hook and reads it in its record-reporting form — but a
wrapper around one is called as written and reports no position.

**Parameters:**
- `ctx` (BibtexDiscoveryContext): The buffer being scanned

**Returns:**
- `string[]`: File names, unresolved

### `discovery.gap_package(ctx)`

Find the bibliographies of the GAP package the buffer belongs to, reading the
package rather than the buffer. Returns nothing when the buffer declares a
`<Bibliography>` of its own (the `gapdoc` hook covers that case), when the
buffer has no file, or when no `PackageInfo.g` is found upward from it.
Otherwise the package's documentation directory — `doc`, or the `dir` named in
`makedoc.g` — is read for the main manual (`_main.xml`, `main.xml`,
`manual.xml`, `<PackageName>.xml`, then the remaining XML files), and its
`<Bibliography Databases="…"/>` declaration is used. When no manual declares
one, AutoDoc's convention is used instead: the `bib` named in `makedoc.g`, or
`<PackageName>.bib` from `PackageInfo.g`, inside the documentation directory.

Results are absolute paths, carrying `.bib` already, and are cached per package
root against the modification times and sizes of every file and directory read.
Files above the size caps (64 KiB for GAP files, 1 MiB for XML) are skipped.

Each result is a record naming the manual that declared it, which
`:checkhealth blink-cmp-bibtex` shows; a path derived from AutoDoc's convention
was never declared anywhere and names no file. No line is reported: the
declaration is read from the document as one joined text.

**Parameters:**
- `ctx` (BibtexDiscoveryContext): The buffer being scanned

**Returns:**
- `BibtexDiscoveryResult[]`: Absolute bibliography paths, which need not exist

### `discovery.builtin`

Table mapping the built-in names `latex`, `yaml`, `typst`, `gapdoc` and
`gap_package` to their functions.

### `discovery.defaults`

The dispatch shipped with the plugin, and the value `config` copies into
`discovery`. Every hook that reads the buffer sits under `'*'`, because that
kind of discovery is filetype agnostic; `gap_package`, which probes the file
system, is shipped under `gap`, `xml` and `autodoc` only. Both are looser than
`matchers.defaults`, where the filetype decides which citation syntax applies.

### `discovery.normalize(name, value, filetype)`

Normalize a configured value into a spec, accepting the same forms as
`matchers.normalize` (`false`, `true`, a built-in name, a function, or a spec
table) with the same inheritance of shipped fields. Invalid values are skipped
with one warning per name.

**Returns:**
- `BibtexDiscoverySpec|nil`

### `discovery.chain(filetype, opts)`

Build the ordered hook chain for a filetype. Entries under the filetype key
override same-named `'*'` entries; ties break on the name.

Unlike `matchers.chain`, this falls back to `discovery.defaults` when `opts` or
`opts.discovery` is absent, because `find_bib_files_from_buffer` is public and
is called without options. Pass `discovery = false` to run no hooks at all, or
`discovery = true` for the shipped ones. A value that is neither a table nor
one of those booleans is reported once and treated as absent; `matchers.chain`
accepts the same shorthands, where absent means an empty chain.

**Returns:**
- `BibtexDiscoverySpec[]`

### `discovery.collect_detailed(ctx)`

Run the chain and concatenate what the hooks report, in chain order, keeping
the hook that reported each name and the position it reported. A hook may
report a name or a `{ name = …, line = …, file = … }` record, in a list or on
its own; the shipped buffer-reading hooks return names, and are read here in an
internal record-reporting form instead, so their positions are known without
changing what they return to their own callers. Each hook is called inside
`pcall`; one that raises, or returns something other than a name or a list of
names and records, is reported once and skipped for that filetype. A record is
checked as it is read: `name` must be a string, `line` an integer when present,
and `file` a path when present, since the report renders all three.
Names are returned unresolved — `resolve_bib_paths` resolves and deduplicates
them.

**Returns:**
- `BibtexDiscoveryEntry[]`

### `discovery.collect(ctx)`

The names `collect_detailed` reports, in the same order. Callers that only
resolve paths need nothing else.

**Returns:**
- `string[]`

### Types

```lua
--- @class BibtexDiscoveryContext
--- @field bufnr number
--- @field filetype string|nil
--- @field lines string[]      -- shared between hooks; read-only
--- @field bufname string|nil
--- @field dir string|nil      -- the buffer's directory
--- @field root string|nil     -- the project root, from root_markers
--- @field opts table

--- @class BibtexDiscoveryResult  -- what a hook may report instead of a name
--- @field name string
--- @field line integer|nil  -- the line the declaration was found on, 1-based
--- @field file string|nil   -- the declaring file, when it is not the buffer

--- @class BibtexDiscoveryEntry   -- what collect_detailed returns
--- @field name string            -- with the hook's extension rule applied
--- @field hook string            -- the hook that reported it
--- @field line integer|nil
--- @field file string|nil

--- @alias BibtexDiscoveryReport string|BibtexDiscoveryResult
--- @alias BibtexDiscoveryFn fun(ctx: BibtexDiscoveryContext): BibtexDiscoveryReport[]|BibtexDiscoveryReport|nil

--- @class BibtexDiscoverySpec
--- @field name string
--- @field find BibtexDiscoveryFn
--- @field priority number       -- lower runs first (default 50); output order only
--- @field extension boolean|nil -- when not false, extensionless results get '.bib'
```

A hook takes only the context, with no leading subject argument. This differs
from a matcher, which takes the text it inspects as its first parameter: the
lines a hook reads are already part of its context.

## Module: blink-cmp-bibtex.path

Path helpers shared by the scanner and the discovery hooks, so that a hook can
resolve what it finds without depending on `scan`, which depends on this module.

### `path.joinpath(base, relative)` / `path.normalize(path)` / `path.is_absolute(path)`

Join two components, expand and normalize a path (`~` included), and tell an
absolute path from a relative one.

### `path.find_root(bufname, markers)`

Find the project root of a buffer: the directory of the nearest marker found
upward from the buffer's own directory, or that directory when no marker is
found. An empty or unnamed buffer starts from the working directory.

**Parameters:**
- `bufname` (string): Buffer file name
- `markers` (table): Root marker files or directories, as `root_markers`

**Returns:**
- `string`: The root directory

## Module: blink-cmp-bibtex.scan

BibTeX file discovery and path resolution.

### `scan.find_bib_files_from_buffer_detailed(bufnr, opts)`

Find BibTeX files referenced in a buffer, keeping the hook that reported each
name and the position it reported. Same guards and same order as
`find_bib_files_from_buffer`, which returns the names of these entries.

**Returns:**
- `BibtexDiscoveryEntry[]`

### `scan.find_bib_files_from_buffer(bufnr, opts)`

Find BibTeX files referenced in a buffer by running the discovery hooks
configured for its filetype. See [Buffer Discovery](#buffer-discovery) for the
forms the built-in hooks understand, and
[Module: blink-cmp-bibtex.discovery](#module-blink-cmp-bibtexdiscovery) for
registering your own.

**Parameters:**
- `bufnr` (number): Buffer number
- `opts` (table|nil): Configuration options. When omitted, the hooks shipped
  with the plugin are used, so callers that only want the built-in behavior can
  keep calling this with a buffer alone.

**Returns:**
- `string[]`: List of bibliography file names (not full paths)

**Example:**
```lua
local scan = require('blink-cmp-bibtex.scan')
local files = scan.find_bib_files_from_buffer(0)  -- Current buffer
```

### `scan.resolve_bib_sources(bufnr, opts)`

Resolve every bibliography a buffer asks for, with where each came from. Same
order and deduplication as `resolve_bib_paths` — buffer discovery, `files`,
`global_files`, the expanded `search_paths`, then `local_bib.target` — except
that nothing is dropped: a path reported twice keeps an origin per report, and
a path with nothing behind it is returned with `exists = false` rather than
skipped. Each path is stat'ed once.

Paths are identified by what they point at, so a file reached through a
symbolic link — a linked project directory, or `/var` against `/private/var` on
macOS — is one source carrying every origin that named it, rather than one per
spelling. `path` is that resolved path; a path with nothing behind it cannot be
resolved and keeps the spelling it was declared with.

**Parameters:**
- `bufnr` (number): Buffer number
- `opts` (table|nil): Configuration options

**Returns:**
- `BibtexBibSource[]`: The bibliographies, in resolution order

```lua
--- @class BibtexBibSource
--- @field path string     -- normalized absolute path
--- @field exists boolean
--- @field is_dir boolean
--- @field origins BibtexBibOrigin[]  -- everything that reported this path

--- @class BibtexBibOrigin
--- @field kind 'buffer'|'files'|'global_files'|'search_paths'|'local_bib'
--- @field detail string   -- the raw option value, glob pattern or declared name
--- @field hook string|nil -- the discovery hook, for a buffer origin
--- @field file string|nil -- the declaring file, when it is not the buffer
--- @field line integer|nil
```

### `scan.resolve_bib_paths(bufnr, opts)`

Resolve all BibTeX file paths for a buffer. Combines buffer-discovered files,
manual files, and search paths; the sources `resolve_bib_sources` found that
exist and are not directories.

**Parameters:**
- `bufnr` (number): Buffer number
- `opts` (table): Configuration options

**Returns:**
- `string[]`: List of resolved absolute file paths

### `scan.global_set(opts, bufnr)`

Build the set of global bibliographies for a buffer, by resolving its sources
and reading their origins. A global file is exactly a path that resolution
reached through `global_files`, anchored and keyed the way resolution anchored
and keyed it, so a relative entry lands on the project root rather than on the
working directory, and a file listed under one spelling is recognized when the
buffer reaches it under another.

`scan.resolve_options(opts, bufnr)` resolves `files`, `global_files` and
`search_paths` once, into `{ files = …, global_files = …, search_paths = … }`,
and `resolve_bib_sources` accepts that table as its third argument. A caller
that also counts or inspects the options passes it in, so that a function-valued
option runs once rather than once per reading.

A caller that has already resolved the sources should read them with
`scan.global_set_from_sources(sources)` instead: resolving twice calls a
function-valued option twice, and it could answer differently the second time.
`scan.paths_from_sources(sources)` gives the same list `resolve_bib_paths`
returns.

**Returns:**
- `table<string, boolean>`

### `scan.is_global_path(path, set)`

Whether a path is one of the configured global bibliographies, against a set
built by `global_set`. A path that is already a key is answered from the set;
any other is resolved first, which costs a system call, so a caller classifying
the same path repeatedly should remember the answer. A caller holding the
sources the set was built from can read `set[source.path]` directly.

**Returns:**
- `boolean`

## Module: blink-cmp-bibtex.local_bib

Local bibliography file management for copying entries from global to project-local files.

### `local_bib.resolve_target(opts, cwd)`

Resolve the target bib file based on configuration.

**Parameters:**
- `opts` (table): The local_bib configuration
- `cwd` (string, optional): The current working directory

**Returns:**
- `string|nil`: The resolved target path, or nil if not found

**Resolution priority:**
1. `opts.targets[cwd]` - Per-directory target
2. `opts.target` - Explicit target path
3. `opts.patterns` - First matching pattern (or first pattern if `create_if_missing` is true)

### `local_bib.key_exists_in_file(path, key)`

Check if a citation key already exists in a file.

**Parameters:**
- `path` (string): The file path to check
- `key` (string): The citation key to look for

**Returns:**
- `boolean`: True if the key exists in the file

### `local_bib.create_empty_file(path)`

Create an empty bib file with a comment header.

**Parameters:**
- `path` (string): The file path to create

**Returns:**
- `boolean`: True if file was created successfully

### `local_bib.append_entry(path, raw)`

Append a BibTeX entry to a file.

**Parameters:**
- `path` (string): The file path to append to
- `raw` (string): The raw BibTeX entry text

**Returns:**
- `boolean`: True if entry was appended successfully

**Notes:**
- Ensures a blank line between entries
- Creates parent directories if needed

### `local_bib.copy_entry(key, raw, opts)`

Copy a BibTeX entry to the local bib file.

**Parameters:**
- `key` (string): The citation key to copy
- `raw` (string): The raw BibTeX entry text
- `opts` (table): The local_bib configuration

**Returns:**
- `boolean`: True if entry was copied successfully

**Example:**
```lua
local local_bib = require('blink-cmp-bibtex.local_bib')
local_bib.copy_entry('Smith2023', '@article{Smith2023, ...}', {
  enabled = true,
  target = 'plus.bib',
  create_if_missing = true,
  notify_on_add = true,
})
```

## Preview Styles

### APA Style (default)

Provides author-year citation format with detailed multi-line documentation.

**Detail format:** `Author (Year) – Title (Container)`

**Documentation format:**
```
Author (Year).
Title.
Journal, Volume(Number), Pages.
DOI/URL
```

### IEEE Style

Provides IEEE-style citation format with quoted titles.

**Detail format:** `Author "Title," Journal vol. Volume, no. Number, pp. Pages, Year.`

**Documentation format:**
```
Author, "Title," Journal, vol. Volume, no. Number, pp. Pages, Year.
Publisher.
DOI: xxx / URL: xxx
```

## LaTeX Accent Support

The parser automatically converts common LaTeX accent commands to UTF-8:

- Diacritics: `{\"a}` → `ä`, `{\'e}` → `é`, `{\`o}` → `ò`
- Special characters: `\aa` → `å`, `\ss` → `ß`, `\o` → `ø`
- Combining marks: `\^`, `\~`, `\.`, `\=`, `\u`, `\v`, `\H`, `\c`, `\k`, `\r`

## Citation Command Support

The following citation commands are supported:

- Standard: `\cite`, `\citep`, `\citet`
- BibLaTeX: `\parencite`, `\textcite`, `\footcite`, `\smartcite`, `\autocite`, `\nocite`
- Pandoc: `[@key]`, `@key`
- Typst: `@key`, `#cite(<key>)` (Typst buffers only)
- GAPDoc: `<Cite Key="key"/>` (after opting `gap`, `xml` or `autodoc` into `filetypes`)

All LaTeX commands support optional arguments for pre/post notes:
```latex
\parencite[see][p. 42]{key}
\textcite[]{key}
```

## Source Indicators

When using both local and global bibliography files, completion items display
nuanced indicators showing where each entry comes from:

| Indicator | Meaning |
|-----------|---------|
| `[L]` | Entry exists **only** in local bibliography |
| `[G]` | Entry exists **only** in global bibliography |
| `[L=G]` | Entry exists in **both**, content is **identical** |
| `[L≠G]` | Entry exists in **both**, content **differs** |

Indicators only appear when your configuration includes both local and global
sources. If all entries come from the same source type (e.g., only local files),
no indicators are shown.

When an entry exists in both local and global files, the completion menu shows
the local version (deduplication prefers local).

This feature is enabled by default. Set `source_indicator = false` to disable.

## Buffer Discovery

The plugin automatically discovers BibTeX files from:

1. **LaTeX commands** in `.tex` files:
   - `\addbibresource{file.bib}`
   - `\bibliography{file}`
   - `\addglobalbib{file.bib}`
   - `\addsectionbib{file.bib}`

2. **YAML front matter** in Markdown files:
   ```yaml
   ---
   bibliography: references.bib
   ---
   ```

   Or with multiple files:
   ```yaml
   ---
   bibliography:
     - file1.bib
     - file2.bib
   ---
   ```

3. **Typst declarations** in `.typ` files:
   - `#bibliography("refs.bib")`, including declarations inside `#import`ed files

4. **GAPDoc declarations** in XML documents:
   ```xml
   <Bibliography Databases="manual, gapdoc" Style="alpha"/>
   ```
   Names are comma-separated and given without the `.bib` extension, which is
   appended automatically. `Style` is ignored, and BibXMLext databases (named
   with their full `.xml` name) are skipped.

5. **Configured search paths** relative to project root
6. **Manual file paths** from configuration

Items 1-4 are discovery hooks and can be reordered, disabled per filetype, or
joined by your own; see
[Module: blink-cmp-bibtex.discovery](#module-blink-cmp-bibtexdiscovery).
