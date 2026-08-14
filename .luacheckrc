std = 'luajit'
unused_args = false
allow_defined_top = true
read_globals = {
  'vim',
}
exclude_files = { '.tests' }
files['tests/**/*.lua'] = {
  read_globals = {
    'describe',
    'it',
    'before_each',
    'after_each',
    'MiniTest',
    'assert',
  },
}
