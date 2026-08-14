vim.env.LAZY_STDPATH = '.repro'
local bootstrap_url = 'https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua'
local bootstrap = vim.fn.system({ 'curl', '-fsS', bootstrap_url })
assert(vim.v.shell_error == 0, 'failed to download the lazy.nvim bootstrap: ' .. bootstrap)
assert(load(bootstrap, 'lazy.nvim bootstrap'), 'downloaded lazy.nvim bootstrap is not valid Lua')()

require('lazy.minit').repro({
  spec = {
    { dir = vim.uv.cwd(), opts = {} },
    {
      'saghen/blink.cmp',
      version = '*',
      opts = {
        sources = {
          default = { 'bibtex', 'lsp', 'path', 'buffer' },
          providers = {
            bibtex = { name = 'bibtex', module = 'blink-cmp-bibtex' },
          },
        },
      },
    },
  },
})
