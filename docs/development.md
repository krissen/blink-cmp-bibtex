# Development Guide

This guide provides technical details for developers working on blink-bibtex.

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

### Manual Testing

1. **Basic completion:**
   ```tex
   \cite{<trigger completion>
   ```

2. **Multi-key citations:**
   ```tex
   \cite{key1,key2,<trigger completion>
   ```

3. **Optional arguments:**
   ```tex
   \parencite[see][p. 42]{<trigger completion>
   ```

4. **Pandoc style:**
   ```markdown
   [@<trigger completion>
   ```

5. **File discovery:**
   - Test `\addbibresource{file.bib}`
   - Test YAML `bibliography:` field
   - Test search_paths globs

### Testing Checklist

Before submitting changes:

- [ ] Test in LaTeX file (`.tex`)
- [ ] Test in Markdown file (`.md`)
- [ ] Test with multiple BibTeX files
- [ ] Test with large BibTeX files (>1000 entries)
- [ ] Test cache invalidation (modify .bib file)
- [ ] Verify previews display correctly
- [ ] Check for Lua errors in `:messages`
- [ ] Test with custom configuration

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
:lua vim.print(require('blink-bibtex.cache'))
```

### Check loaded files

```lua
:lua vim.print(require('blink-bibtex.scan').resolve_bib_paths(0, require('blink-bibtex.config').get()))
```

### Check parsed entries

```lua
:lua vim.print(require('blink-bibtex.parser').parse_file('references.bib'))
```

## Release Process

1. Update CHANGELOG.md with new version
2. Update version references in documentation
3. Create git tag: `git tag -a v1.x.x -m "Release v1.x.x"`
4. Push tag: `git push origin v1.x.x`
5. Create GitHub release from tag
6. Update README.md if installation instructions change

## Resources

- [blink.cmp documentation](https://github.com/Saghen/blink.cmp)
- [Neovim Lua guide](https://neovim.io/doc/user/lua-guide.html)
- [BibTeX format specification](http://www.bibtex.org/Format/)
- [LaTeX citation commands](https://www.overleaf.com/learn/latex/Bibliography_management_with_biblatex)
