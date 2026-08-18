# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

blink-cmp-bibtex is a native BibTeX/Hayagriva completion source for [blink.cmp](https://github.com/Saghen/blink.cmp). It provides citation key completion with APA/IEEE-style previews in LaTeX, Typst, Markdown, and R Markdown buffers.

## Development Commands

### Tests
```sh
./scripts/test   # or: make test — runs nvim -l tests/minit.lua --minitest
```
The harness bootstraps lazy.nvim, blink.cmp and luassert into `.tests/`, so the
first run needs network access and `python3` on `PATH` (hererocks).

### Linting and formatting
```sh
make lint        # luacheck lua/ plugin/ tests/ repro.lua
make fmt         # stylua lua/ plugin/ tests/ repro.lua
make fmt-check   # stylua --check lua/ plugin/ tests/ repro.lua
```
Both are enforced in CI (`.github/workflows/ci.yml`), together with the test
suite on Neovim v0.10.4, stable and nightly.

### Manual verification
```sh
nvim -u repro.lua   # clean Neovim with blink.cmp and this plugin only
```

## Architecture

Eleven modules under `lua/blink-cmp-bibtex/`:

1. **config.lua** - Default settings, `setup()` and `extend()` functions for configuration. List options replace defaults; keyed maps are merged
2. **parser.lua** - BibTeX/Hayagriva parsing with LaTeX accent normalization to UTF-8
3. **scan.lua** - Path resolution: runs the discovery hooks for the buffer, then resolves, expands globs and deduplicates against `files`, `global_files` and `search_paths`
4. **cache.lua** - Mtime-based caching of parsed entries
5. **matchers.lua** - Citation matchers (`latex`, `pandoc`, `typst`, `gapdoc`), the shipped per-filetype dispatch (`M.defaults`, which config.lua copies), normalization of user-configured matchers, priority ordering and dispatch
6. **local_bib.lua** - Local bibliography management (copy entries from global to project-local files)
7. **health.lua** - `:checkhealth blink-cmp-bibtex`, reports the resolved config, both the matcher and discovery chains, and the bibliographies the current buffer resolves with their origins
8. **discovery.lua** - Buffer bibliography discovery (`latex`, `yaml`, `typst`, `gapdoc` hooks, plus `gap_package`, which reads the GAP package around the buffer), the shipped dispatch (`M.defaults`, which config.lua copies), normalization of user-configured hooks and chain execution
9. **registry.lua** - Shared bookkeeping for both extension points: warn-once, error rendering and per-filetype failure tracking
10. **path.lua** - Path helpers (`joinpath`, `normalize`, `is_absolute`, `find_root`) shared by scan.lua and discovery.lua
11. **init.lua** - blink.cmp source implementation (`Source:enabled`, `Source:get_trigger_characters`, `Source:get_completions`, `Source:resolve`, `Source:execute`)

**Data flow**: Buffer → discovery.lua (hooks report declared files) → scan.lua (resolve and deduplicate paths) → cache.lua (mtime check) → parser.lua (parse if needed) → matchers.lua (citation prefix at cursor) → init.lua (format & filter) → blink.cmp

Entry point: `plugin/blink-cmp-bibtex.lua`

## Key Implementation Details

- Uses `vim.uv or vim.loop` pattern for Neovim 0.9+ compatibility
- Citation command detection handles optional arguments: `\cite[see][p. 42]{key}`
- Multi-key citations supported: `\cite{key1,key2,key3}` and `[@key1; @key2]`
- Typst support includes following `#import` statements to find bibliography declarations
- Preview styles (APA, IEEE) are extensible via `preview_styles` table in init.lua

## Language Requirements

**IMPORTANT: All written content in this project MUST be in English only.**

This includes:
- Code comments (inline and block)
- Documentation files (README, docs/, etc.)
- Commit messages
- JSDoc annotations
- Error messages and notifications
- Variable and function names

No exceptions. Do not use Swedish or any other language.

## Code Style

- **Indentation**: 2 spaces (see `.editorconfig`)
- **Documentation**: JSDoc-style comments with `@param`, `@return`, `@module`
- **Naming**: `snake_case` for functions and variables
- **Error handling**: Use `pcall` for operations that might fail; never crash the editor
- **Async**: Use `vim.schedule` for callbacks that call Neovim API

## Commit Format

This repository uses **Conventional Commits**, which overrides any global
`(scope)` commit convention. The commit history is the input to release-please,
which generates `CHANGELOG.md`, the version bump and the GitHub release.

```
<type>[optional scope]: <description>
```

Types: `feat` (minor bump), `fix`/`perf` (patch bump), `docs`, `test`,
`refactor`, `ci`, `chore` (no release). English, imperative, lower case, no
trailing period. One commit per logical change. Breaking changes use `feat!:` or
a `BREAKING CHANGE:` footer; pre-1.0 these bump the minor version.

Never reference AI assistance anywhere — not in commits, code comments, docs,
PR descriptions, issues or releases.

## Testing Checklist

Before submitting changes:
- Run `./scripts/test` — the full spec suite must be green
- Run `make lint` and `make fmt-check`
- Add or update specs under `tests/` for the behavior you changed
- For UI-facing changes, verify manually with `nvim -u repro.lua`:
  - `.tex` files with various citation commands
  - `.md` files with Pandoc-style `[@key]` citations
  - `.typ` files with `@key` and `#cite(<key>)` syntax
  - Cache invalidation by modifying a `.bib` file
- Check `:checkhealth blink-cmp-bibtex` and `:messages` for Lua errors

## Debugging

```lua
-- Inspect resolved bib paths
:lua vim.print(require('blink-cmp-bibtex.scan').resolve_bib_paths(0, require('blink-cmp-bibtex.config').get()))

-- Inspect the same paths with the option or declaration each came from
:lua vim.print(require('blink-cmp-bibtex.scan').resolve_bib_sources(0, require('blink-cmp-bibtex.config').get()))

-- Inspect parsed entries from a file
:lua vim.print(require('blink-cmp-bibtex.parser').parse_file('references.bib'))

-- Inspect cache state
:lua vim.print(require('blink-cmp-bibtex.cache'))
```

## License

MIT - all code must be original (no GPL-licensed code reuse).
