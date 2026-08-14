# blink-cmp-bibtex

BibTeX and Hayagriva completion source for [blink.cmp](https://github.com/Saghen/blink.cmp).
It indexes `\addbibresource` declarations and project bibliography files to offer
citation-key completion together with APA-styled previews in LaTeX, Typst,
Markdown and R Markdown buffers.

---

[Features](#features) · [Installation](#installation) · [Configuration](#configuration) · [Custom citation matchers](#custom-citation-matchers) · [Custom bib discovery](#custom-bib-discovery) · [Usage](#usage) · [Health check](#health-check) · [Alternatives](#alternatives)

---

## Why this plugin?

`blink-cmp-bibtex` was created to bring BibTeX citation completion to [blink.cmp](https://github.com/Saghen/blink.cmp) users. While excellent alternatives exist, they have different trade-offs:

- **[VimTeX](https://github.com/lervag/vimtex)** is the comprehensive LaTeX plugin with built-in completion, syntax highlighting, compilation, and more. It can integrate with blink.cmp through [blink.compat](https://github.com/saghen/blink.compat) using its `omni` source. However, VimTeX is primarily a full-featured LaTeX environment rather than a focused completion source.

- **[cmp-bibtex](https://github.com/texlaborg/cmp-bibtex)** is the established citation source for `nvim-cmp`. It's GPL-licensed and tightly coupled to the `cmp` API, making it unsuitable for direct use with blink.cmp.

`blink-cmp-bibtex` fills the gap by providing a native, MIT-licensed completion source designed specifically for blink.cmp. It focuses solely on citation completion with minimal overhead, making the transition from cmp seamless for users with citation-heavy workflows in LaTeX, Typst, Markdown, and R Markdown.

## Features

- Native blink.cmp source implemented in pure Lua (no `blink.compat`).
- Discovers `.bib` files (BibTeX) and `.yml`/`.yaml` files (Hayagriva) from the current buffer, configured search paths or an explicit `files` list.
- For Typst files, follows `#import` statements to find bibliography declarations in imported files.
- Parses entries lazily, normalizes common LaTeX accents (e.g. `{"a}`, `\aa`)
  and caches the results with modification-time tracking.
- Supports common citation commands (`\cite`, `\parencite`, `\textcite`,
  `\smartcite`, `\footcite`, `\nocite`, Pandoc `[@key]`, …) including optional
  pre/post notes. Typst syntax (`@key`, `#cite(<key>)`) applies in `typst`
  buffers, where it takes precedence over the Pandoc forms.
- Generates APA-inspired previews showing author, year, title and container data
  with selectable templates (APA default, IEEE optional).
- Shows `[L]`/`[G]` source indicators to distinguish local (project) from global
  (shared) bibliography files.
- Ships with sane defaults yet allows overriding behavior via
  `require("blink-cmp-bibtex").setup()` or provider-level `opts`.
- Lets you add citation syntaxes per filetype through the `matchers` option
  (GAPDoc's `<Cite Key="…"/>` is included), without patching the plugin.
- Lets you add bibliography discovery for your own conventions through the
  `discovery` option, alongside the built-in LaTeX, YAML, Typst and GAPDoc
  declarations.
- Reports the resolved configuration through `:checkhealth blink-cmp-bibtex`.

## Installation

Example with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "saghen/blink.cmp",
  dependencies = {
    "krissen/blink-cmp-bibtex",
  },
  opts = {
    sources = {
      default = function(list)
        table.insert(list, "bibtex")
        return list
      end,
      providers = {
        bibtex = {
          module = "blink-cmp-bibtex",
          name = "BibTeX",
          min_keyword_length = 2,
          score_offset = 10,
          async = true,
          opts = {
            -- provider-level overrides (optional)
          },
        },
      },
    },
  },
}
```

## Configuration

Call `require("blink-cmp-bibtex").setup()` early in your config to change defaults.
Only values you set will override the built-ins.

```lua
require("blink-cmp-bibtex").setup({
  filetypes = { "tex", "plaintex", "markdown", "rmd", "typst" },
  files = { "references.bib" },                              -- Local project files
  global_files = { vim.fn.expand("~/research/master.bib") }, -- Global shared files
  search_paths = { "bib/*.bib" },
  root_markers = { ".git", "texmf.cnf" },
  citation_commands = { "cite", "parencite", "textcite" },
  preview_style = "ieee",      -- or "apa" (default)
  source_indicator = true,     -- Show source indicators (default: true)
})
```

**List options replace the defaults.** `filetypes`, `citation_commands`,
`files`, `global_files`, `search_paths` and `root_markers` are lists, and a list
you configure is used as-is instead of being merged into the built-in one. The
`citation_commands = { "cite", "parencite", "textcite" }` above therefore leaves
`\footcite` and friends unrecognized. Table options that are keyed maps (such as
`local_bib` and `matchers`) are still merged key by key, so you only need to
spell out the keys you want to change.

### Custom citation matchers

A *matcher* inspects the text before the cursor and decides whether the cursor
sits inside a citation, and which key prefix has been typed so far. The
`matchers` option maps a filetype to the matchers used in that filetype; the
`'*'` key applies to every filetype. Entries under a filetype key override
same-named entries under `'*'`.

The defaults, which live in
`require("blink-cmp-bibtex.matchers").defaults`, are:

```lua
matchers = {
  ['*'] = {
    latex = { priority = 10 },   -- \cite{key}, \parencite[see][p. 42]{key}
    pandoc = { priority = 30 },  -- [@key], @key
  },
  typst = {
    typst = { priority = 20 },   -- @key, #cite(<key>)
  },
  -- Shipped but dormant: 'gap', 'xml' and 'autodoc' are not in the default
  -- `filetypes`, so these only activate once you opt in (see below).
  gap = { gapdoc = { priority = 5, trigger_characters = { '"' } } },
  xml = { gapdoc = { priority = 5, trigger_characters = { '"' } } },
  autodoc = { gapdoc = { priority = 5, trigger_characters = { '"' } } },
}
```

Every value is normalized into a matcher spec. The accepted forms are:

| Value | Meaning |
|-------|---------|
| `false` | Disable the matcher for this filetype |
| `true` | Enable the built-in matcher with the same name |
| `"pandoc"` | Use the named built-in matcher under a different key |
| `function(text, opts, ctx)` | Use this function as the matcher |
| `{ match = fn, ... }` | A spec table; without `match` the built-in of the same name is used |

Whenever the match function comes from a built-in, the spec fields you leave out
are inherited from what the plugin ships for that matcher — first the entry for
this filetype, then the one under `'*'`. Re-enabling `gapdoc` with `true` in an
`xml` buffer therefore keeps its priority of 5 and its `"` trigger character
rather than falling back to bare defaults. Fields you do spell out always win.

Spec fields:

- `match` (function) – the matcher function itself.
- `priority` (number, default `50` when neither you nor the built-in supplies
  one) – lower runs first; the first matcher that returns a result wins. Ties
  are broken by name.
- `sanitize` (boolean) – whether a matched prefix is reduced to the key being
  typed. Sanitization splits on the matcher's separators, keeps the last
  segment, trims whitespace and strips a leading `@`, which is what makes
  `\cite{a,b,c` and `[@a; @b` complete the final key. Set `sanitize = false`
  when keys are used verbatim (the built-in `gapdoc` matcher does this).
- `separators` (string, default `",;"`) – the characters that separate keys in
  a multi-key citation. The built-in `latex` and `typst` matchers use `","`
  only, since a semicolon is an ordinary character in a key there; `pandoc`
  uses `",;"`.
- `trigger_characters` (string[]) – characters that should open the completion
  menu in buffers of this filetype. They are only offered while the source is
  enabled, so a `"` trigger for XML never fires in a LaTeX buffer.

A matcher receives the line text up to the cursor, the resolved options, and a
context table with `bufnr`, `filetype`, `line` and `col`. It returns `nil` for
no match, or a table with:

- `prefix` (string, required) – the citation-key prefix typed so far.
- `trigger` (string) – a name for the syntax that matched.
- `command` (string) – the citation command that matched, when applicable.
- `sanitize` (boolean) – override the spec's sanitization for this match.

Matchers are called through `pcall`. One that raises is reported once and
skipped for the rest of the session, so a broken matcher never breaks
completion.

**Disabling a built-in:**

```lua
require("blink-cmp-bibtex").setup({
  matchers = {
    ['*'] = { pandoc = false },  -- no Pandoc citations anywhere
    markdown = { pandoc = true }, -- except in Markdown
  },
})
```

**Reusing a built-in matcher:**

```lua
local matchers = require("blink-cmp-bibtex.matchers")

require("blink-cmp-bibtex").setup({
  matchers = {
    mytype = {
      -- matchers.latex, matchers.pandoc, matchers.typst and matchers.gapdoc
      -- are all callable directly; matchers.builtin maps names to functions.
      brackets = { match = matchers.pandoc, priority = 20 },
    },
  },
})
```

#### Example: GAPDoc

[GAPDoc](https://github.com/frankluebeck/GAPDoc) documentation is XML and cites
with `<Cite Key="CR1" Where="(5.22)"/>`. The `gapdoc` matcher for that syntax
ships with the plugin but is dormant, because `gap`, `xml` and `autodoc` are not
in the default `filetypes`. Adding them is all the configuration needed:

```lua
require("blink-cmp-bibtex").setup({
  -- `filetypes` is a list, so repeat the defaults you still want.
  filetypes = { "tex", "plaintex", "markdown", "rmd", "typst", "gap", "xml" },
})
```

Typing `<Cite Key="CR` then completes the key, and `"` opens the menu. The
document's own `<Bibliography Databases="..."/>` declaration is scanned, so the
bibliography needs no configuration; `files` and `search_paths` remain available
for bibliographies that live elsewhere.

If your citation syntax differs, register your own matcher instead:

```lua
require("blink-cmp-bibtex").setup({
  filetypes = { "tex", "markdown", "xml" },
  files = { "doc/manual.bib" },
  matchers = {
    xml = {
      -- Complete <Ref BibKey="..."/> as well as GAPDoc's own <Cite Key="..."/>.
      refkey = {
        priority = 5,
        sanitize = false,
        trigger_characters = { '"' },
        match = function(text)
          local prefix = text:match('<Ref%s+[^>]-BibKey%s*=%s*"([^"]*)$')
          if prefix then
            return { prefix = prefix, trigger = "refkey" }
          end
        end,
      },
    },
  },
})
```

Run `:checkhealth blink-cmp-bibtex` to see the matcher chain that a filetype
actually resolves to.

### Custom bib discovery

A *discovery hook* reads the current buffer and reports the bibliography files
it declares. This is what finds `\addbibresource{refs.bib}` in a LaTeX file or
`bibliography: refs.bib` in Markdown front matter, and it is the same kind of
registry as the matchers above: the `discovery` option maps a filetype to the
hooks that run in it, and `'*'` applies to every filetype.

The defaults, which live in
`require("blink-cmp-bibtex.discovery").defaults`, are:

```lua
discovery = {
  ['*'] = {
    latex = { priority = 10 },   -- \addbibresource{}, \bibliography{}
    yaml = { priority = 20 },    -- bibliography: in Markdown front matter
    typst = { priority = 30 },   -- #bibliography(), following #import
    gapdoc = { priority = 40, extension = false }, -- <Bibliography Databases="">
  },
}
```

Note the contrast with `matchers`: **every** discovery hook sits under `'*'`,
because a declaration is worth finding wherever it appears — an
`\addbibresource` in a Markdown buffer is found today, and moving the LaTeX
hook under `tex` would silently stop finding it. Only narrow a hook to a
filetype when the syntax genuinely cannot occur elsewhere.

A hook receives a context and returns the file names it found, as a list, a
single string, or nil:

```lua
require("blink-cmp-bibtex").setup({
  discovery = {
    ['*'] = {
      -- Read a project convention: a plain-text file listing bibliographies.
      manifest = {
        priority = 5,
        find = function(ctx)
          -- Cheap guard first: hooks run on every completion request, so scan
          -- for a literal marker before doing anything expensive.
          for _, line in ipairs(ctx.lines) do
            local path = line:match('^%%%% bib: (.+)$')
            if path then
              return path
            end
          end
          return nil
        end,
      },
    },
    -- Markdown documents in this project never use LaTeX declarations.
    markdown = { latex = false },
  },
})
```

The context carries `bufnr`, `filetype`, `lines`, `bufname`, `dir` (the
buffer's directory, for resolving relative paths) and `opts`. Its `lines` table
is shared with the other hooks, so treat it as read-only.

Values are normalized exactly as matcher values are — `false` disables, `true`
enables the built-in of the same name, a string names a built-in, a function is
the hook itself, and a table is a spec — with the same inheritance of shipped
fields. Spec fields:

- `find` (function) — the hook itself.
- `priority` (number, default `50`) — lower runs first. Unlike matchers, every
  hook runs; priority decides only the order of the results.
- `extension` (boolean) — when not `false`, a name without an extension gets
  `.bib` appended, so `\bibliography{references}` resolves to `references.bib`.
  Set `extension = false` when the hook returns finished file names.

Relative paths are resolved against the buffer's directory, with the project
root as a fallback, exactly like the built-in results.

`discovery = false` turns buffer discovery off entirely, leaving `files`,
`global_files` and `search_paths` as the only sources, and `discovery = true`
restores the shipped hooks. The `matchers` option takes the same two
shorthands. Any other value that is neither of those nor a table is reported
through `vim.notify` once and ignored, so a typo degrades the configuration
instead of breaking completion.

Run `:checkhealth blink-cmp-bibtex` to see the discovery chain that a filetype
actually resolves to.

### Source indicators

When you have both local (project) and global (shared) bibliography files,
completion items display nuanced indicators showing where each entry comes from
and whether local and global versions differ:

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

To disable indicators, set `source_indicator = false` in your configuration.

### Local bibliography management

When working with both global (shared) and local (project) bibliography files, you can
automatically copy entries from global files to a local project file. This is useful
when you want to maintain a self-contained project bibliography while drawing from a
master reference library.

```lua
require("blink-cmp-bibtex").setup({
  global_files = { vim.fn.expand("~/research/master.bib") },
  search_paths = { "references.bib" },
  local_bib = {
    enabled = true,
    target = "plus.bib",         -- Local file to copy entries to
    auto_add = true,             -- Copy on completion accept
    create_if_missing = true,    -- Create target if it doesn't exist
    notify_on_add = true,        -- Show notification when entry is added
    duplicate_check = true,      -- Skip if entry already exists (default: true)
  },
})
```

**How it works:**

1. When you accept a completion for a `[G]` (global-only) entry, the BibTeX entry
   is automatically copied to your `local_bib.target` file.
2. The entry appears in future completions as `[L=G]` (exists in both, identical).
3. You can also manually copy entries using the `:BibTeXCopyToLocal [key]` command.

**Configuration options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable local bibliography management |
| `target` | string | `nil` | Path to local bib file (relative to project root) |
| `targets` | table | `{}` | Per-directory targets: `{ ["/path/to/project"] = "refs.bib" }` |
| `patterns` | table | `{ "local.bib", "references.bib" }` | Fallback patterns to search |
| `auto_add` | boolean | `false` | Automatically copy global entries on accept |
| `create_if_missing` | boolean | `false` | Create target file if it doesn't exist |
| `notify_on_add` | boolean | `true` | Show notification when entry is added |
| `notify_on_duplicate` | boolean | `false` | Show notification for duplicate entries |
| `duplicate_check` | boolean | `true` | Check for existing entries before adding |

### Preview styles

`preview_style` picks the formatter for the completion detail and documentation
pane. The built-in options are:

- `apa` (default) – Author-year summaries with multiline APA documentation.
- `ieee` – IEEE-inspired strings using quoted titles plus volume/issue metadata.

Custom styles can be added by extending `require("blink-cmp-bibtex").setup()` with a
`preview_style` that matches one of the registered templates.

### Buffer discovery

- `\addbibresource{}`, `\addglobalbib`, `\addsectionbib` and legacy
  `\bibliography{}` statements are scanned inside TeX buffers.
- Missing `.bib` extensions are appended automatically so classic
  `\bibliography{references}` declarations resolve to `references.bib` on disk.
- Buffer-local paths resolve relative to the current file's directory (with the
  project root as a fallback) so chapter subdirectories can reference sibling
  bibliographies.
- Markdown YAML metadata lines such as `bibliography: references.bib` are
  respected.
- Typst `#bibliography()` declarations are detected, including those in imported files via `#import` statements.
- GAPDoc `<Bibliography Databases="manual, gapdoc"/>` declarations are scanned in
  XML documents. Names are comma-separated and carry no `.bib` extension, which
  is appended automatically; `.xml` (BibXMLext) databases are skipped, as are
  declarations inside XML comments, CDATA sections and processing instructions.
- Both BibTeX (`.bib`) and Hayagriva (`.yml`, `.yaml`) bibliography files are supported and automatically detected based on file extension.
- Every one of these is a discovery hook, and the set is configurable: see
  [Custom bib discovery](#custom-bib-discovery) to add a syntax, reorder the
  hooks, or disable one per filetype.
- `opts.search_paths` accepts either file paths or glob patterns relative to the
  detected project root (based on `opts.root_markers`). These are treated as
  **local** sources.
- `opts.files` is a list of absolute or `vim.fn.expand`-friendly paths that are
  always included. These are treated as **local** sources (shown with `[L]`
  indicator when source indicators are enabled).
- `opts.global_files` is a list of paths to shared/master bibliography files.
  These are treated as **global** sources (shown with `[G]` indicator).

  **Note:** Source indicators (`[L]`, `[G]`, `[L=G]`, `[L≠G]`) only appear when
  you have both local and global sources configured. If you only use `files`
  and `search_paths` without `global_files`, no indicators are shown since all
  entries are implicitly local.

### blink.cmp provider options

Any table supplied as `providers.bibtex.opts` in the blink.cmp configuration is
merged into the global setup options. This enables per-source overrides for
`files`, `filetypes`, preview style, etc.

## Usage

`blink-cmp-bibtex` triggers autocompletion as you type citation keys in your documents:

### In LaTeX files

Start typing a citation command followed by an opening brace, then begin typing
the citation key. For example, when you have a BibTeX entry with the key
`Niemi2025`:

```latex
\cite{Nie
```

As you type `Nie`, blink.cmp will show matching citation keys. The completion
menu displays each key with a concise APA-style summary, and selecting an entry
shows expanded details in the documentation pane.

This works with all supported citation commands: `\parencite{`, `\textcite{`,
`\footcite{`, `\smartcite{`, `\autocite{`, `\nocite{`, `\citep{`, `\citet{`, and
more. Optional arguments are also supported (e.g., `\cite[see][42]{Nie`).

### In Markdown and R Markdown files

Use Pandoc-style citations with the `@` symbol. For the same `Niemi2025` entry:

```markdown
@Nie
```

Or within brackets for inline citations:

```markdown
[@Nie
```

Multiple references are supported using semicolons:

```markdown
[@ref1; @Nie
```

As you type, blink.cmp shows matching keys with the same preview information as
in LaTeX mode.

### In Typst files

Typst supports both simple `@key` citations and the more explicit `#cite(<key>)`
syntax. Both are completed in buffers with the `typst` filetype only:

```typst
@Nie
```

Or using the cite function:

```typst
#cite(<Nie
```

The restriction to `typst` buffers is deliberate. In Markdown and R Markdown
only the Pandoc forms (`@key` at a word boundary and `[@key`) apply, so an
address such as `user@example` no longer opens the completion menu. To use the
Typst forms in another filetype, add the `typst` matcher to it — see
[Custom citation matchers](#custom-citation-matchers).

#### Typst bibliography formats

Typst supports two bibliography file formats:

1. **BibTeX** (`.bib` files) - Traditional format used in LaTeX
2. **Hayagriva** (`.yml` or `.yaml` files) - Typst's native YAML-based bibliography format

Both formats are automatically detected and parsed. For example:

```typst
#bibliography("references.bib")  // BibTeX format
#bibliography("references.yml")  // Hayagriva format
```

#### Import tracking

The plugin automatically follows Typst `#import` statements to find bibliography declarations in imported files. For example:

```typst
// main.typ
#import "refs.typ": refs
@Nie  // Completion works here!

// refs.typ (in the same directory)
#let refs = bibliography("references.bib")
```

The plugin will detect the `bibliography()` call in `refs.typ` and index the entries from `references.bib`, even though it's not directly declared in the main file.

### In GAPDoc / XML files

GAPDoc documentation cites with an XML tag, optionally carrying a `Where`
attribute:

```xml
<Cite Key="Nie
```

The matcher for this syntax ships with the plugin but stays dormant until you
add `gap`, `xml` or `autodoc` to `filetypes` — see
[Custom citation matchers](#custom-citation-matchers). Typing `"` opens the
menu, and keys are inserted verbatim (no multi-key splitting).

The bibliography is discovered from the document itself. A declaration such as

```xml
<Bibliography Databases="manual, gapdoc" Style="alpha"/>
```

resolves to `manual.bib` and `gapdoc.bib` next to the document, following
GAPDoc's rule that BibTeX databases are named without their `.bib` extension.
The optional `Style` attribute is ignored, and BibXMLext databases (named with
their full `.xml` name) are skipped, since this plugin reads BibTeX and
Hayagriva. If your bibliography lives elsewhere, list it under `files` or
`search_paths` as usual.

### Completion details

blink.cmp renders two panes for each matched item:

- The completion row shows the citation key with an APA-style summary. Source
  indicators (`[L]`, `[G]`, etc.) appear on the right side of the menu.
- The documentation pane (typically shown below or beside the menu) expands the
  same entry with publisher/journal, place, DOI/URL, etc.

Each completion item exposes:

- `label`: the citation key.
- `detail`: APA-like string (`Author (Year) – Title`).
- `labelDetails.description`: source indicator (`[L]`, `[G]`, `[L=G]`, `[L≠G]`).
- `documentation`: multi-line APA preview covering author/editor, year, title,
  container, publisher and DOI/URL when available.

## Health check

```vim
:checkhealth blink-cmp-bibtex
```

The report shows the resolved `filetypes`, preview style and file counts, and
lists the matcher chain each configured filetype resolves to, in the order the
matchers run. A filetype that has matchers but is missing from `filetypes` is
warned about, since those matchers can never fire — except for the ones shipped
dormant with the plugin (`gap`, `xml`, `autodoc`), which are reported as
information.

## Documentation

- [API Reference](docs/api.md) – Detailed API documentation for all modules
- [Development Guide](docs/development.md) – Architecture, coding style, and contribution guidelines
- [Specification](docs/spec.md) – High-level feature specification and design goals

## Alternatives

If `blink-cmp-bibtex` doesn't fit your needs, consider these alternatives:

### VimTeX

[VimTeX](https://github.com/lervag/vimtex) is a comprehensive LaTeX plugin offering completion, syntax highlighting, compilation, PDF viewing, and much more. It provides BibTeX completion through multiple methods:

- **Native completion**: VimTeX has built-in `omni` completion for citations
- **blink.cmp integration**: Use VimTeX with blink.cmp via [blink.compat](https://github.com/saghen/blink.compat) and its `omni` source ([setup guide](https://cmp.saghen.dev/configuration/sources#vimtex))
- **Full LaTeX environment**: If you need more than just citations (e.g., compilation, navigation, text objects), VimTeX is the go-to choice

### cmp-bibtex

[cmp-bibtex](https://github.com/texlaborg/cmp-bibtex) is the established BibTeX source for `nvim-cmp`. If you're using `nvim-cmp`, this is the recommended option. Note that it's GPL-licensed and not directly compatible with blink.cmp.

### Other community sources

The blink.cmp ecosystem has various [community sources](https://cmp.saghen.dev/configuration/sources#community-sources) for different completion needs. Check the documentation for the latest list.

## Migration from blink-bibtex

If you're upgrading from the old `blink-bibtex` name, you'll need to update your configuration in three places:

### 1. Update your lazy.nvim plugin specification

**Before:**

```lua
{
  "saghen/blink.cmp",
  dependencies = {
    "krissen/blink-bibtex",
  },
  -- ...
}
```

**After:**

```lua
{
  "saghen/blink.cmp",
  dependencies = {
    "krissen/blink-cmp-bibtex",
  },
  -- ...
}
```

### 2. Update the module name in your blink.cmp config

**Before:**

```lua
providers = {
  bibtex = {
    module = "blink-bibtex",
    -- ...
  },
}
```

**After:**

```lua
providers = {
  bibtex = {
    module = "blink-cmp-bibtex",
    -- ...
  },
}
```

### 3. Update any direct setup() calls

**Before:**

```lua
require("blink-bibtex").setup({
  -- config
})
```

**After:**

```lua
require("blink-cmp-bibtex").setup({
  -- config
})
```

### 4. Clean up the old plugin

After updating your config, remove the old plugin directory and reinstall:

```vim
:Lazy clean
:Lazy sync
```

Then restart Neovim.

## Contributing

Issues and pull requests are welcome. Please read
[`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, coding guidelines and
the review process. A high-level specification lives in [`docs/spec.md`](docs/spec.md)
so new features stay consistent with the overall goals.

For detailed technical information, see the [Development Guide](docs/development.md).
For API details, consult the [API Reference](docs/api.md).

## License

MIT © 2025 Kristian Niemi
