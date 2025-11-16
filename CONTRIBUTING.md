# Contributing to blink-bibtex

Thanks for helping improve blink-bibtex! This document captures the project
expectations so every change stays consistent with the MIT-licensed, blink-first
vision outlined in `docs/spec.md`.

## Prerequisites

- Neovim 0.9+ with [blink.cmp](https://github.com/Saghen/blink.cmp) installed for
  manual testing.
- Lua 5.1+ toolchain for linting/formatting. We recommend
  [stylua](https://github.com/JohnnyMorganz/StyLua) and
  [luacheck](https://github.com/lunarmodules/luacheck), though they are not hard
  requirements.

## Development workflow

1. Fork the repository and create a branch for your change.
2. Read the [Development Guide](docs/development.md) for architecture details and
   coding conventions.
3. Run any available linting/formatting tools (`stylua`, `luacheck`, etc.) before
   committing. Even if they are not installed locally, please keep `.editorconfig`
   conventions (tabs vs spaces, trailing whitespace) intact.
4. Manually test in Neovim when touching the completion source:
   ```sh
   nvim --headless -u NONE -c "set rtp+=." -c "lua require('blink-bibtex')" -c q
   ```
   Add citation commands in `.tex`/`.md` buffers and ensure completions and APA
   previews appear as described in the README.
5. Update documentation alongside behavior changes. In particular, keep:
   - `README.md` (user-facing instructions) synchronized with implemented behavior
   - `docs/spec.md` (feature specification) aligned with the design
   - `docs/api.md` (API documentation) updated for API changes
   - `CHANGELOG.md` (changelog) with your changes in the Unreleased section
6. Open a pull request that describes the motivation, implementation details,
   and any testing performed. Reference related issues when applicable.

## Coding guidelines

- All Lua code lives under `lua/blink-bibtex/` and follows the module layout in
  the spec (`config.lua`, `parser.lua`, `scan.lua`, `cache.lua`, `init.lua`).
- Use JSDoc-style comments for all functions with `@param`, `@return`, and
  description annotations.
- Avoid copying GPL-licensed code. Implement features from scratch or cite a
  permissive source.
- Prefer small, composable helpers over large monolithic functions. Async work
  should schedule callbacks using blink.cmp's recommended patterns.
- Use `vim.uv or vim.loop` for backward compatibility with older Neovim versions.
- Follow the patterns in `docs/development.md` for error handling and API usage.

## Documentation

All documentation should be written in English. When adding or modifying features:

1. Update inline code comments (JSDoc-style)
2. Update `docs/api.md` for API changes
3. Update `README.md` for user-visible changes
4. Add entry to `CHANGELOG.md` in the Unreleased section
5. Update `docs/development.md` if adding architectural patterns

## Reporting issues

Please include Neovim version, blink.cmp version, the relevant snippet of your
configuration, and (when possible) a minimal BibTeX file that reproduces the
problem. This makes it easier to replicate issues across environments.

For bugs, include:
- Steps to reproduce
- Expected behavior
- Actual behavior
- Any error messages from `:messages`

For feature requests, include:
- Use case description
- Example of how you'd like it to work
- Whether you're willing to contribute the implementation

Happy hacking!

