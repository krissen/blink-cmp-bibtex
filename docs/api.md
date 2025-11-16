# API Documentation

This document provides detailed API documentation for `blink-bibtex` modules.

## Module: blink-bibtex

Main entry point for the BibTeX completion source.

### `Source.new(opts)`

Create a new source instance.

**Parameters:**
- `opts` (table, optional): Configuration overrides

**Returns:**
- `Source`: A new source instance

**Example:**
```lua
local source = require('blink-bibtex').new({
  filetypes = { "tex", "markdown" }
})
```

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

### `Source.setup(opts)`

Configure global default settings.

**Parameters:**
- `opts` (table, optional): Configuration options
  - `filetypes` (string[]): Supported filetypes (default: `{"tex", "plaintex", "markdown", "rmd"}`)
  - `files` (string[]): List of absolute BibTeX file paths to always include
  - `search_paths` (string[]): Glob patterns or paths to search for BibTeX files
  - `root_markers` (string[]): Files/directories indicating project root (default: `{".git", "latexmkrc", "texmf.cnf"}`)
  - `citation_commands` (string[]): LaTeX citation commands to recognize
  - `preview_style` (string): Preview template name (`"apa"` or `"ieee"`, default: `"apa"`)
  - `max_entries` (number): Maximum entries to collect (default: 4000)

**Example:**
```lua
require('blink-bibtex').setup({
  filetypes = { "tex", "markdown" },
  preview_style = "ieee",
  search_paths = { "references.bib", "bib/*.bib" }
})
```

## Module: blink-bibtex.config

Configuration management for blink-bibtex.

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

## Module: blink-bibtex.cache

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

### `cache.invalidate(path)`

Invalidate cache for a specific file path.

**Parameters:**
- `path` (string): The file path to invalidate

## Module: blink-bibtex.parser

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
local parser = require('blink-bibtex.parser')
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

## Module: blink-bibtex.scan

BibTeX file discovery and path resolution.

### `scan.find_bib_files_from_buffer(bufnr)`

Find BibTeX files referenced in a buffer.

**Parameters:**
- `bufnr` (number): Buffer number

**Returns:**
- `string[]`: List of bibliography file names (not full paths)

**Example:**
```lua
local scan = require('blink-bibtex.scan')
local files = scan.find_bib_files_from_buffer(0)  -- Current buffer
```

### `scan.resolve_bib_paths(bufnr, opts)`

Resolve all BibTeX file paths for a buffer. Combines buffer-discovered files, manual files, and search paths.

**Parameters:**
- `bufnr` (number): Buffer number
- `opts` (table): Configuration options

**Returns:**
- `string[]`: List of resolved absolute file paths

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

The following LaTeX citation commands are supported:

- Standard: `\cite`, `\citep`, `\citet`
- BibLaTeX: `\parencite`, `\textcite`, `\footcite`, `\smartcite`, `\autocite`, `\nocite`
- Pandoc: `[@key]`, `@key`

All commands support optional arguments for pre/post notes:
```latex
\parencite[see][p. 42]{key}
\textcite[]{key}
```

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
