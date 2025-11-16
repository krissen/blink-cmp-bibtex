# blink-bibtex specification

This document is a lightweight feature description for `blink-bibtex`, a native
source for [blink.cmp](https://github.com/Saghen/blink.cmp). The goal is to
reimplement the functionality provided by `cmp-bibtex` (a GPL-3 source for
nvim-cmp) with a fresh, MIT-licensed codebase that targets blink.cmp directly.

## Functional requirements

- Provide completion items for citation keys defined in BibTeX files.
- Discover BibTeX files via multiple mechanisms:
  - `\addbibresource{}` declarations in the current buffer.
  - YAML metadata in Markdown (e.g. `bibliography: references.bib`).
  - Glob search relative to the project root (`opts.search_paths`).
  - Manually supplied file list via `opts.files`.
  - Resolve buffer-discovered paths relative to the buffer's directory, with the
    project root serving as a fallback when needed.
- Support all citation-style commands typically covered by `cmp-bibtex`,
  including `\cite`, `\parencite`, `\footcite`, `\textcite`, `\smartcite`,
  `\nocite`, Pandoc style citations (`[@key]`), and square-bracket variants.
- Recognize optional arguments (`\cite[see][123]{key}`) and offer completion for
  the final key segment only.
- Provide `pre` and `post` note handling: completion must fire even when there
  are optional arguments between the command and the `{`.
- Generate APA-inspired previews for each completion item. The preview should
  include author/editor, publication year, title, and source container
  (journal/book/publisher). Normalize common LaTeX accent/diacritic commands so
  that previews render human-friendly UTF-8 (e.g. `{"a}` → `ä`, `\aa` → `å`).
  The documentation callback should format a multi-line preview (rendered in
  blink.cmp's documentation pane) while the detail string shows a concise
  one-liner directly in the completion menu.
- Respect filetype restrictions (`opts.filetypes`). Only activate on LaTeX,
  Markdown, R Markdown, and other explicitly configured filetypes.
- Provide asynchronous completion so that large BibTeX files do not block the UI.
- Cache parsed BibTeX files and reload them when the modification time changes.

## Non-functional requirements

- Entire implementation must be original (no GPL-licensed code reuse) and
  released under the MIT license.
- Lua modules should be organized as follows:
  - `config.lua`: defaults plus `setup` and merge helpers.
  - `parser.lua`: standalone BibTeX parser that extracts entry metadata and
    performs minimal LaTeX-to-UTF8 conversions.
  - `scan.lua`: buffer/project inspectors that find relevant `.bib` files.
  - `cache.lua`: memoized storage keyed by file path with mtime checks.
  - `init.lua`: blink.cmp source implementation.
- Provide a `plugin/blink-bibtex.lua` entrypoint so that the source can be
  configured automatically when added to the runtime path.
- Supply `README.md` coverage for installation (lazy.nvim), configuration, and
  feature summary. Include snippets showing how to register the source with
  blink.cmp and how to call `require("blink-bibtex").setup()`. Document the
  MIT rationale (why this plugin exists alongside `cmp-bibtex`), reference
  related blink.cmp sources, and describe how to contribute.
- Provide a `CONTRIBUTING.md` that captures workflow expectations (linting,
  testing, documentation updates) so new contributors can get started quickly.
- Default configuration should be practical without user input, but each module
  must allow overriding values through `setup()` or provider `opts` in blink.cmp.
- Ensure style tooling (`.editorconfig`, `.luacheckrc`) matches common blink
  source conventions.
