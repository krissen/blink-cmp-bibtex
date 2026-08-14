std = 'luajit'
unused_args = false
allow_defined_top = true
read_globals = {
  'vim',
}
exclude_files = { '.tests' }
-- Bootstrap files assign vim.env before loading lazy.nvim.
files['tests/minit.lua'] = { globals = { 'vim' } }
files['repro.lua'] = { globals = { 'vim' } }
-- Specs stub members of vim (vim.notify) around assertions, so vim must be
-- writable here rather than read-only.
files['tests/**/*.lua'] = {
  globals = { 'vim' },
  read_globals = {
    'describe',
    'it',
    'before_each',
    'after_each',
    'MiniTest',
  },
}
