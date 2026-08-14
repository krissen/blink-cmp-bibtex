vim.env.LAZY_STDPATH = '.tests'
local bootstrap_url = 'https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua'
local bootstrap = vim.fn.system({ 'curl', '-fsS', bootstrap_url })
assert(vim.v.shell_error == 0, 'failed to download the lazy.nvim bootstrap: ' .. bootstrap)
assert(load(bootstrap, 'lazy.nvim bootstrap'), 'downloaded lazy.nvim bootstrap is not valid Lua')()

require('lazy.minit').setup({
  spec = {
    { 'saghen/blink.cmp', version = '*', opts = {} },
  },
})
