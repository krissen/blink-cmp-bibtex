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

### `matchers.normalize(name, value)`

Normalize a configured matcher value into a spec.

**Parameters:**
- `name` (string): The configuration key the value was found under
- `value` (any): `false`/`nil` (disabled), `true` (built-in of the same name), a
  string (named built-in), a function, or a spec table

**Returns:**
- `BibtexMatcherSpec|nil`: The normalized spec, or nil when disabled or invalid

Invalid values are reported once per name through `vim.notify` and skipped.

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

**Reports:**
- `filetypes`, `preview_style`, `max_entries` and the number of configured
  `files` and `global_files`
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

## Module: blink-cmp-bibtex.scan

BibTeX file discovery and path resolution.

### `scan.find_bib_files_from_buffer(bufnr)`

Find BibTeX files referenced in a buffer.

**Parameters:**
- `bufnr` (number): Buffer number

**Returns:**
- `string[]`: List of bibliography file names (not full paths)

**Example:**
```lua
local scan = require('blink-cmp-bibtex.scan')
local files = scan.find_bib_files_from_buffer(0)  -- Current buffer
```

### `scan.resolve_bib_paths(bufnr, opts)`

Resolve all BibTeX file paths for a buffer. Combines buffer-discovered files, manual files, and search paths.

**Parameters:**
- `bufnr` (number): Buffer number
- `opts` (table): Configuration options

**Returns:**
- `string[]`: List of resolved absolute file paths

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

3. **Configured search paths** relative to project root
4. **Manual file paths** from configuration
