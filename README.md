# blink-bibtex

BibTeX completion source for [blink.cmp](https://github.com/Saghen/blink.cmp).
It indexes `\addbibresource` declarations and project BibTeX files to offer
citation-key completion together with APA-styled previews in LaTeX, Markdown and
R Markdown buffers.

## Background

`blink-bibtex` exists because [`cmp-bibtex`](https://github.com/texlaborg/cmp-bibtex)
—the long-standing source for `nvim-cmp`—is GPL-licensed and tied to the
`cmp` API. Rather than porting that code (which would keep the GPL
requirements), this project re-implements the feature set from scratch under
the MIT license and exposes it directly to blink.cmp. The goal is to make the
transition from cmp to blink seamless for users with citation-heavy workflows.

## Features

- Native blink.cmp source implemented in pure Lua (no `blink.compat`).
- Discovers `.bib` files from the current buffer, configured search paths or an
  explicit `files` list.
- Parses entries lazily, normalizes common LaTeX accents (e.g. `{"a}`, `\aa`)
  and caches the results with modification-time tracking.
- Supports common citation commands (`\cite`, `\parencite`, `\textcite`,
  `\smartcite`, `\footcite`, `\nocite`, Pandoc `[@key]`, …) including optional
  pre/post notes.
- Generates APA-inspired previews showing author, year, title and container data.
- Ships with sane defaults yet allows overriding behavior via
  `require("blink-bibtex").setup()` or provider-level `opts`.

## Installation

Example with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "saghen/blink.cmp",
  dependencies = {
    "krissen/blink-bibtex",
  },
  opts = {
    sources = {
      default = function(list)
        table.insert(list, "bibtex")
        return list
      end,
      providers = {
        bibtex = {
          module = "blink-bibtex",
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

Call `require("blink-bibtex").setup()` early in your config to change defaults.
Only values you set will override the built-ins.

```lua
require("blink-bibtex").setup({
  filetypes = { "tex", "plaintex", "markdown", "rmd" },
  files = { vim.fn.expand("~/research/global.bib") },
  search_paths = { "references.bib", "bib/*.bib" },
  root_markers = { ".git", "texmf.cnf" },
  citation_commands = { "cite", "parencite", "textcite" },
  preview_style = "apa",
})
```

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

Insert a citation command (`\parencite{`, `\textcite[see][42]{`, or Pandoc style
`[@`) and trigger completion via your blink.cmp mapping. blink.cmp renders two
panes for each item:

- The completion row itself ("detail" column) contains the key plus a concise
  APA-style summary (`Author (Year) – Title`).
- The documentation pane (typically shown below or beside the menu) expands the
  same entry with publisher/journal, place, DOI/URL, etc.

With that in mind, each completion item exposes:

- `label`: the citation key.
- `detail`: short APA-like string (`Author (Year) – Title`).
- `documentation`: multi-line APA preview covering author/editor, year, title,
  container, publisher and DOI/URL when available.

## Roadmap

- Additional preview styles beyond APA.
- Smarter detection of bibliography files in mixed-language projects.

## Related projects

- [`cmp-bibtex`](https://github.com/texlaborg/cmp-bibtex) – the inspiration for
  this plugin's behavior and command coverage.
- [`blink-cmp-dictionary`](https://github.com/Kaiser-Yang/blink-cmp-dictionary)
  – reference implementation for blink.cmp provider structure.
- [`blink-cmp-git`](https://github.com/Kaiser-Yang/blink-cmp-git) – another
  community source that informed the async completion wiring here.

## Contributing

Issues and pull requests are welcome. Please read
[`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, coding guidelines and
the review process. A high-level specification lives in [`docs/spec.md`](docs/spec.md)
so new features stay consistent with the overall goals.

## License

MIT © 2025 Kristian Niemi
