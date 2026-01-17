local ok, source = pcall(require, 'blink-cmp-bibtex')
if not ok then
  return
end

if type(source.setup) == 'function' then
  source.setup()
end

-- Create user command for copying entries to local bib
vim.api.nvim_create_user_command('BibTeXCopyToLocal', function(args)
  source.copy_to_local_bib(args.args ~= '' and args.args or nil)
end, {
  nargs = '?',
  desc = 'Copy a BibTeX entry to the local bib file',
})

-- Setup auto_add via CompleteDone if configured
local function setup_auto_add()
  local config = require('blink-cmp-bibtex.config')
  local opts = config.get()
  if not opts.local_bib or not opts.local_bib.enabled or not opts.local_bib.auto_add then
    return
  end

  vim.api.nvim_create_autocmd('CompleteDone', {
    group = vim.api.nvim_create_augroup('BlinkCmpBibtexAutoAdd', { clear = true }),
    callback = function()
      local completed_item = vim.v.completed_item
      if not completed_item then
        return
      end
      -- Check if this is from our source via user_data
      local user_data = completed_item.user_data
      if type(user_data) == 'string' then
        local ok_decode, decoded = pcall(vim.json.decode, user_data)
        if ok_decode then
          user_data = decoded
        end
      end
      if type(user_data) == 'table' and user_data.source == 'blink-cmp-bibtex' and user_data.key then
        source.copy_to_local_bib(user_data.key)
      end
    end,
  })
end

-- Defer auto_add setup to ensure config is loaded
vim.schedule(setup_auto_add)
