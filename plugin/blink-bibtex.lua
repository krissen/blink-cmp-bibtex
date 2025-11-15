if not pcall(require, 'blink.cmp') then
  return
end

local ok, source = pcall(require, 'blink-bibtex')
if not ok then
  return
end

source.setup()

pcall(vim.api.nvim_create_user_command, 'BlinkBibtexHealth', function()
  vim.cmd('checkhealth blink-bibtex')
end, {
  desc = 'Run :checkhealth blink-bibtex for troubleshooting',
})
