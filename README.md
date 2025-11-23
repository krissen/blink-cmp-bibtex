# blink-cmp-bibtex

> **⚠️ IMPORTANT**: This plugin was recently renamed from `blink-bibtex` to `blink-cmp-bibtex`. If you're upgrading, please see the [Migration Guide](#migration-from-blink-bibtex) below.

BibTeX completion source for [blink.cmp](https://github.com/Saghen/blink.cmp).
It indexes `\addbibresource` declarations and project BibTeX files to offer
citation-key completion together with APA-styled previews in LaTeX, Typst,
Markdown and R Markdown buffers.

## Why this plugin?

`blink-cmp-bibtex` was created to bring BibTeX citation completion to [blink.cmp](https://github.com/Saghen/blink.cmp) users. While excellent alternatives exist, they have different trade-offs:

- **[VimTeX](https://github.com/lervag/vimtex)** is the comprehensive LaTeX plugin with built-in completion, syntax highlighting, compilation, and more. It can integrate with blink.cmp through [blink.compat](https://github.com/saghen/blink.compat) using its `omni` source. However, VimTeX is primarily a full-featured LaTeX environment rather than a focused completion source.

- **[cmp-bibtex](https://github.com/texlaborg/cmp-bibtex)** is the established citation source for `nvim-cmp`. It's GPL-licensed and tightly coupled to the `cmp` API, making it unsuitable for direct use with blink.cmp.

`blink-cmp-bibtex` fills the gap by providing a native, MIT-licensed completion source designed specifically for blink.cmp. It focuses solely on citation completion with minimal overhead, making the transition from cmp seamless for users with citation-heavy workflows in LaTeX, Typst, Markdown, and R Markdown.

## Features

- Native blink.cmp source implemented in pure Lua (no `blink.compat`).
- Discovers `.bib` files from the current buffer, configured search paths or an
  explicit `files` list.
- Parses entries lazily, normalizes common LaTeX accents (e.g. `{"a}`, `\aa`)
  and caches the results with modification-time tracking.
- Supports common citation commands (`\cite`, `\parencite`, `\textcite`,
  `\smartcite`, `\footcite`, `\nocite`, Pandoc `[@key]`, …) including optional
  pre/post notes.
- Generates APA-inspired previews showing author, year, title and container data
  with selectable templates (APA default, IEEE optional).
- Ships with sane defaults yet allows overriding behavior via
  `require("blink-cmp-bibtex").setup()` or provider-level `opts`.

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
  filetypes = { "tex", "plaintex", "markdown", "rmd" },
  files = { vim.fn.expand("~/research/global.bib") },
  search_paths = { "references.bib", "bib/*.bib" },
  root_markers = { ".git", "texmf.cnf" },
  citation_commands = { "cite", "parencite", "textcite" },
  preview_style = "ieee", -- or "apa" (default)
})
```

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
- `opts.search_paths` accepts either file paths or glob patterns relative to the
  detected project root (based on `opts.root_markers`).
- `opts.files` is a list of absolute or `vim.fn.expand`-friendly paths that are
  always included.

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

As you type, blink.cmp shows matching keys with the same preview information as
in LaTeX mode.

### Completion details

blink.cmp renders two panes for each matched item:

- The completion row itself ("detail" column) contains the key plus a concise
  APA-style summary (`Author (Year) – Title`).
- The documentation pane (typically shown below or beside the menu) expands the
  same entry with publisher/journal, place, DOI/URL, etc.

Each completion item exposes:

- `label`: the citation key.
- `detail`: short APA-like string (`Author (Year) – Title`).
- `documentation`: multi-line APA preview covering author/editor, year, title,
  container, publisher and DOI/URL when available.

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
