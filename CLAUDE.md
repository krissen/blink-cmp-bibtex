# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

blink-cmp-bibtex is a native BibTeX/Hayagriva completion source for [blink.cmp](https://github.com/Saghen/blink.cmp). It provides citation key completion with APA/IEEE-style previews in LaTeX, Typst, Markdown, and R Markdown buffers.

## Development Commands

### Manual Testing
```sh
# Basic load test
nvim --headless -u NONE -c "set rtp+=." -c "lua require('blink-cmp-bibtex')" -c q
```

### Linting
```sh
luacheck lua/
```

### Formatting (optional but recommended)
```sh
stylua lua/
```

## Architecture

Five modules under `lua/blink-cmp-bibtex/`:

1. **config.lua** - Default settings, `setup()` and `extend()` functions for configuration
2. **parser.lua** - BibTeX/Hayagriva parsing with LaTeX accent normalization to UTF-8
3. **scan.lua** - File discovery from `\addbibresource{}`, YAML metadata, Typst `#bibliography()`, `#import` statements, and glob patterns
4. **cache.lua** - Mtime-based caching of parsed entries
5. **init.lua** - blink.cmp source implementation (`Source:get_completions`, `Source:resolve`)

**Data flow**: Buffer → scan.lua (file discovery) → cache.lua (mtime check) → parser.lua (parse if needed) → init.lua (format & filter) → blink.cmp

Entry point: `plugin/blink-cmp-bibtex.lua`

## Key Implementation Details

- Uses `vim.uv or vim.loop` pattern for Neovim 0.9+ compatibility
- Citation command detection handles optional arguments: `\cite[see][p. 42]{key}`
- Multi-key citations supported: `\cite{key1,key2,key3}` and `[@key1; @key2]`
- Typst support includes following `#import` statements to find bibliography declarations
- Preview styles (APA, IEEE) are extensible via `preview_styles` table in init.lua

## Code Style

- **Indentation**: 2 spaces (see `.editorconfig`)
- **Documentation**: JSDoc-style comments with `@param`, `@return`, `@module`
- **Naming**: `snake_case` for functions and variables
- **Error handling**: Use `pcall` for operations that might fail; never crash the editor
- **Async**: Use `vim.schedule` for callbacks that call Neovim API

## Testing Checklist

Before submitting changes:
- Test in `.tex` files with various citation commands
- Test in `.md` files with Pandoc-style `[@key]` citations
- Test in `.typst` files with `@key` and `#cite(<key>)` syntax
- Verify cache invalidation by modifying a `.bib` file
- Check `:messages` for Lua errors

## Debugging

```lua
-- Inspect resolved bib paths
:lua vim.print(require('blink-cmp-bibtex.scan').resolve_bib_paths(0, require('blink-cmp-bibtex.config').get()))

-- Inspect parsed entries from a file
:lua vim.print(require('blink-cmp-bibtex.parser').parse_file('references.bib'))

-- Inspect cache state
:lua vim.print(require('blink-cmp-bibtex.cache'))
```

## License

MIT - all code must be original (no GPL-licensed code reuse).
