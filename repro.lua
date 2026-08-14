vim.env.LAZY_STDPATH = '.repro'
load(vim.fn.system('curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua'))()

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
