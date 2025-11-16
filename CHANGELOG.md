# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING**: Replaced deprecated `vim.loop` API with `vim.uv` for better Neovim 0.10+ compatibility
- **BREAKING**: Removed fallback to deprecated `vim.tbl_islist` and `vim.tbl_isempty` functions
- Replaced `vim.deepcopy` with custom implementation for better control and forward compatibility
- Optimized string trimming operations using pattern matching instead of multiple gsub calls
- Improved error handling in file I/O operations with better error messages

### Added
- Comprehensive JSDoc-style documentation for all functions and modules
- Module-level documentation with `@module` tags
- Type annotations for function parameters and return values
- Detailed API documentation in `docs/api.md`
- This changelog to track all project changes
- Better error messages when files cannot be opened

### Fixed
- Potential issues with future Neovim versions by using current API conventions
- Improved compatibility with Neovim 0.9+ and 0.10+

### Internal
- Unified trim() function implementation across all modules
- Better code organization with consistent documentation style
- More maintainable codebase with explicit type information

## [1.0.0] - Initial Release

### Added
- BibTeX completion source for blink.cmp
- Support for LaTeX citation commands (\cite, \parencite, \textcite, etc.)
- Support for Pandoc-style citations ([@key])
- Automatic discovery of BibTeX files from buffers
- APA and IEEE preview styles
- LaTeX accent normalization to UTF-8
- Caching with modification time tracking
- Configuration via setup() function
- MIT license (clean-room implementation)

[Unreleased]: https://github.com/krissen/blink-bibtex/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/krissen/blink-bibtex/releases/tag/v1.0.0
