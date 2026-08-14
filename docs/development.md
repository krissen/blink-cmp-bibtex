# Development Guide

This guide provides technical details for developers working on blink-cmp-bibtex.

## Architecture

### Module Organization

The codebase is organized into five main modules:

1. **config.lua**: Configuration management
   - Stores default settings
   - Provides `setup()` and `extend()` for customization
   - Handles merging of user options

2. **parser.lua**: BibTeX parsing
   - Parses BibTeX entries from file content
   - Normalizes LaTeX commands to UTF-8
   - Handles various BibTeX field formats (braced, quoted)

3. **scan.lua**: File discovery
   - Finds BibTeX files from buffer content
   - Resolves paths relative to buffer or project root
   - Supports glob patterns for search paths

4. **cache.lua**: Entry caching
   - Stores parsed entries with mtime tracking
   - Invalidates cache when files change
   - Limits memory usage with configurable max entries

5. **init.lua**: blink.cmp source
   - Implements blink.cmp source interface
   - Detects citation commands in context
   - Generates completion items with previews

### Data Flow

```
Buffer → scan.lua → File paths
              ↓
         cache.lua → Cached entries
              ↓
      parser.lua → Parse if needed
              ↓
         init.lua → Format & filter
              ↓
       blink.cmp → Display completion
```

## Code Style

### Documentation

All functions should have JSDoc-style documentation:

```lua
--- Brief description of what the function does
--- @param name type Description of parameter
--- @param optional type|nil Optional parameter description
--- @return type Description of return value
local function example(name, optional)
  -- implementation
end
```

Module files should start with:

```lua
--- Module name and purpose
--- Brief description of what the module provides
--- @module module.name
```

### Naming Conventions

- **Functions**: Use `snake_case` for all functions
- **Variables**: Use `snake_case` for local variables
- **Constants**: Use `UPPER_SNAKE_CASE` for true constants
- **Private functions**: Mark with `local` keyword
- **Public functions**: Add to module table `M.function_name`

### Error Handling

- Use `pcall` for operations that might fail
- Provide meaningful error messages
- Don't crash the editor - gracefully degrade
- Log warnings for non-critical issues

Example:
```lua
local ok, result = pcall(risky_operation, arg)
if not ok then
  notify(string.format('Operation failed: %s', result))
  return fallback_value
end
```

## API Compatibility

### Neovim Version Support

The plugin supports Neovim 0.9+ with forward compatibility for 0.10+.

**Key compatibility considerations:**

1. **vim.uv vs vim.loop**
   - Use `vim.uv or vim.loop` pattern for backward compatibility
   - `vim.uv` is the new API in Neovim 0.10+

2. **vim.islist vs vim.tbl_islist**
   - Prefer `vim.islist` with fallback
   - `vim.tbl_islist` is deprecated

3. **Table operations**
   - Use `vim.tbl_deep_extend` for merging tables
   - Use `next(tbl) == nil` for empty check

### blink.cmp Integration

The source implements the blink.cmp source interface:

```lua
function Source:get_completions(context, callback)
  -- Must call callback with response table
  -- Must return cancellation function
end

function Source:resolve(item, callback)
  -- Optional: enhance completion items
end
```

**Response format:**
```lua
{
  items = {
    {
      label = "citation_key",
      kind = completion_kind,
      detail = "Short preview",
      documentation = "Detailed preview",
      insertText = "citation_key"
    }
  },
  is_incomplete_forward = true,
  is_incomplete_backward = true
}
```

## Testing

### Running the suite

```sh
./scripts/test          # or: make test
```

The script runs `nvim -l tests/minit.lua --minitest` from the repository root.
`tests/minit.lua` bootstraps [lazy.nvim](https://github.com/folke/lazy.nvim)
into `.tests/` (gitignored) and installs blink.cmp plus `luassert`, so the first
run needs network access. `luassert` is fetched through hererocks, which
requires `python3` on `PATH`.

Every push and pull request runs the same command in CI against Neovim
`v0.10.4`, `stable` and `nightly` (nightly is allowed to fail), alongside
`luacheck` and `stylua --check`:

```sh
make lint      # luacheck lua/ tests/ repro.lua
make fmt       # stylua lua/ tests/ repro.lua
make fmt-check # stylua --check lua/ tests/ repro.lua
```

### Layout

```
tests/
  minit.lua        # harness bootstrap, entry point for scripts/test
  helpers.lua      # fixture paths, fake completion contexts, tmpdir helper
  fixtures/        # .bib, .yml and a small project tree used by the specs
  *_spec.lua       # one spec file per module
```

`tests/helpers.lua` provides the pieces most specs need:

- `helpers.fixture(rel)` resolves a path under `tests/fixtures/` to an absolute
  path, so specs do not depend on the working directory.
- `helpers.ctx(line, col, bufnr)` builds a table shaped like a blink.cmp
  completion context.
- `helpers.with_tmpdir(fn)` runs `fn` in a fresh temporary directory and removes
  it afterwards, including when `fn` raises.

### Writing specs

Specs are run by `mini.test` through lazy.nvim's busted-style wrapper, so they
are written with `describe`, `it` and `before_each`, and assert with `luassert`.
Prefer table-driven cases, generating one `it` per row, so a new syntax or
option is one line rather than one function:

```lua
local assert = require('luassert')
local matchers = require('blink-cmp-bibtex.matchers')
local config = require('blink-cmp-bibtex.config')

describe('matchers.latex', function()
  local cases = {
    { line = '\\cite{Nie', prefix = 'Nie', command = 'cite' },
    { line = '\\parencite[see][p. 42]{Nie', prefix = 'Nie', command = 'parencite' },
  }

  for _, case in ipairs(cases) do
    it('matches ' .. case.line, function()
      local result = matchers.latex(case.line, config.defaults())
      assert.are.same({
        prefix = case.prefix,
        command = case.command,
        trigger = 'latex',
      }, result)
    end)
  end

  it('ignores commands outside citation_commands', function()
    assert.is_nil(matchers.latex('\\unknowncmd{k', config.defaults()))
  end)
end)
```

Use `config.defaults()` rather than `config.get()` in specs; `setup()` mutates
the module-level options and would leak between spec files.

Fixtures belong in `tests/fixtures/`; add a file there rather than writing
BibTeX inline when more than one spec needs it.

### Manual verification

Automated specs cover parsing, discovery, caching and citation detection, but
not the completion menu itself. For UI-facing changes, start a clean Neovim with
the standalone reproduction config:

```sh
nvim -u repro.lua
```

It installs blink.cmp with this plugin registered as the `bibtex` source into
`.repro/`, isolated from your own configuration. It is also what to ask for in
bug reports. Then check:

- [ ] Completion and previews appear in a `.tex` buffer (`\cite{`)
- [ ] Completion appears in a `.md` buffer (`[@`)
- [ ] Completion appears in a `.typ` buffer (`@`, `#cite(<`)
- [ ] Cache invalidation: edit a `.bib` file and complete again
- [ ] `:checkhealth blink-cmp-bibtex` reports the expected matcher chains
- [ ] No Lua errors in `:messages`

## Performance Considerations

### Caching Strategy

- Parse files only when mtime/size changes
- Cache parsed entries in memory
- Limit total entries to prevent memory issues
- Use `vim.schedule` for async operations

### String Operations

- Use pattern matching (`match`) over multiple `gsub` calls
- Avoid repeated string concatenation in loops
- Use `table.concat` for building strings from parts

### File Operations

- Read files in single operation (`read('*a')`)
- Use `pcall` to handle missing files gracefully
- Don't keep file handles open

## Common Pitfalls

### 1. Path Handling

Always use `vim.fs.normalize` for paths:
```lua
path = vim.fs.normalize(path)  -- Good
path = path:gsub('\\', '/')    -- Bad (platform-specific)
```

### 2. Async Operations

Always use `vim.schedule` for callbacks:
```lua
vim.schedule(function()
  -- Safe to call Neovim API here
end)
```

### 3. Table Mutation

Don't modify shared tables:
```lua
local opts = config.get()
opts.files = new_files  -- Bad! Modifies shared config

local opts = vim.tbl_deep_extend('force', {}, config.get())
opts.files = new_files  -- Good! Works on a copy
```

## Adding Features

### Adding a Preview Style

1. Add the style to `preview_styles` table in `init.lua`:

```lua
preview_styles.my_style = {
  detail = function(ctx)
    return string.format('%s - %s', ctx.author, ctx.title)
  end,
  documentation = function(ctx)
    local lines = {}
    table.insert(lines, ctx.author)
    table.insert(lines, ctx.title)
    return table.concat(lines, '\n')
  end
}
```

2. Document it in README.md and docs/api.md

### Adding Citation Commands

Add to `citation_commands` in `config.lua`:

```lua
citation_commands = {
  "cite", "parencite", -- existing
  "mycustomcite",      -- new command
}
```

### Adding File Discovery

Modify `scan.lua`:

1. Add pattern matching in `extract_command_paths` for LaTeX
2. Add parsing in `find_yaml_bibliography` for Markdown
3. Update documentation

## Debugging

### Enable verbose logging

```lua
vim.notify = function(msg, level, opts)
  print(string.format('[%s] %s', opts.title or 'vim', msg))
end
```

### Inspect cache

```lua
:lua vim.print(require('blink-cmp-bibtex.cache'))
```

### Check loaded files

```lua
:lua vim.print(require('blink-cmp-bibtex.scan').resolve_bib_paths(0, require('blink-cmp-bibtex.config').get()))
```

### Check parsed entries

```lua
:lua vim.print(require('blink-cmp-bibtex.parser').parse_file('references.bib'))
```

## Release Process

**Note**: Version management and changelogs are maintained by repository maintainers.

1. Update version references in documentation
2. Create git tag: `git tag -a v1.x.x -m "Release v1.x.x"`
3. Push tag: `git push origin v1.x.x`
4. Create GitHub release from tag
5. Update README.md if installation instructions change

## Resources

- [blink.cmp documentation](https://github.com/Saghen/blink.cmp)
- [Neovim Lua guide](https://neovim.io/doc/user/lua-guide.html)
- [BibTeX format specification](http://www.bibtex.org/Format/)
- [LaTeX citation commands](https://www.overleaf.com/learn/latex/Bibliography_management_with_biblatex)
