local ok, source = pcall(require, 'blink-cmp-bibtex')
if not ok then
  return
end

-- Create user command for copying entries to local bib
vim.api.nvim_create_user_command('BibTeXCopyToLocal', function(args)
  source.copy_to_local_bib(args.args ~= '' and args.args or nil)
end, {
  nargs = '?',
  desc = 'Copy a BibTeX entry to the local bib file',
})
