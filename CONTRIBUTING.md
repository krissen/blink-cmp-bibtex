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
2. Run any available linting/formatting tools (`stylua`, `luacheck`, etc.) before
   committing. Even if they are not installed locally, please keep `.editorconfig`
   conventions (tabs vs spaces, trailing whitespace) intact.
3. Manually test in Neovim when touching the completion source:
   ```sh
   nvim --headless -u NONE -c "set rtp+=." -c "lua require('blink-bibtex')" -c q
   ```
   Add citation commands in `.tex`/`.md` buffers and ensure completions and APA
   previews appear as described in the README.
4. Update documentation alongside behavior changes. In particular, keep
   `README.md` (user-facing instructions) and `docs/spec.md` (feature spec)
   synchronized with the implemented behavior.
5. Open a pull request that describes the motivation, implementation details,
   and any testing performed. Reference related issues when applicable.

## Coding guidelines

- All Lua code lives under `lua/blink-bibtex/` and follows the module layout in
  the spec (`config.lua`, `parser.lua`, `scan.lua`, `cache.lua`, `init.lua`).
- Avoid copying GPL-licensed code. Implement features from scratch or cite a
  permissive source.
- Prefer small, composable helpers over large monolithic functions. Async work
  should schedule callbacks using blink.cmp's recommended patterns.

## Reporting issues

Please include Neovim version, blink.cmp version, the relevant snippet of your
configuration, and (when possible) a minimal BibTeX file that reproduces the
problem. This makes it easier to replicate issues across environments.

Happy hacking!
