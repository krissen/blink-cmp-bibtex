# blink-bibtex

BibTeX completion source for [blink.cmp](https://github.com/Saghen/blink.cmp).
It indexes `\addbibresource` declarations and project BibTeX files to offer
citation-key completion together with APA-styled previews in LaTeX, Markdown and
R Markdown buffers.

## Features

- Native blink.cmp source implemented in pure Lua (no `blink.compat`).
- Discovers `.bib` files from the current buffer, configured search paths or an
  explicit `files` list.
- Parses entries lazily and caches the results with modification-time tracking.
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
  debug = false,
})
```

### Debug logging

- Set `debug = true` to emit verbose tracing via `vim.notify`, including detected
  buffers, resolved bibliography paths and cache activity.
- Provide a custom `log = function(level, message) ... end` callback to redirect
  messages to your preferred logger (e.g. `vim.notify_once`, log files, plenary
  loggers, etc.).
- The callback receives a numeric `level` (matching `vim.log.levels`) and the
  fully formatted string, so you can forward it to any sink:

  ```lua
  require("blink-bibtex").setup({
    debug = true,
    log = function(level, message)
      vim.notify(message, level, { title = "blink-bibtex" })
    end,
  })
  ```
- When `log` is omitted, messages fall back to `vim.notify`. Disabling `debug`
  stops the verbose traces but warnings/errors (e.g. parse failures) are still
  surfaced.

### Health checks

- Run `:BlinkBibtexHealth` (or `:checkhealth blink-bibtex`) inside the target
  buffer to see which filetype is active, which `.bib` files were discovered
  (including manual `files` / `search_paths`) and how many entries were parsed
  from each source.
- Missing files, zero-entry caches, or disabled filetypes are reported as
  warnings so you can adjust `setup()`/buffer directives without hunting
  through log output.
- The health report also reminds you which preview style and logging settings
  are active, making it easier to confirm whether `debug` or custom log sinks
  are configured as expected.

### Buffer discovery

- `\addbibresource{}`, `\addglobalbib`, `\addsectionbib` and legacy
  `\bibliography{}` statements are scanned inside TeX buffers.
- Missing `.bib` extensions are appended automatically so classic
  `\bibliography{references}` declarations resolve to `references.bib` on disk.
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
`[@`) and trigger completion via your blink.cmp mapping. Each item shows:

- `label`: the citation key.
- `detail`: short APA-like string (`Author (Year) – Title`).
- `documentation`: multi-line APA preview covering author/editor, year, title,
  container, publisher and DOI/URL when available.

## Roadmap

- Additional preview styles beyond APA.
- Smarter detection of bibliography files in mixed-language projects.

## License

MIT © 2025 Kristian Niemi
