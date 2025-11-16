# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING**: Repository renamed from `blink-bibtex` to `blink-cmp-bibtex`
- **BREAKING**: Module renamed from `blink-bibtex` to `blink-cmp-bibtex`

### Migration Guide

If you're upgrading from the old `blink-bibtex` name, you'll need to update your configuration:

#### 1. Update your lazy.nvim plugin specification

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

#### 2. Update the module name in your blink.cmp config

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

#### 3. Update any direct setup() calls

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

#### 4. Remove the old plugin directory

After updating your config, remove the old plugin directory and reinstall:

```vim
:Lazy clean
:Lazy sync
```

Or if you prefer to do it manually:
```bash
rm -rf ~/.local/share/nvim/lazy/blink-bibtex
```

Then restart Neovim and run `:Lazy sync`.
