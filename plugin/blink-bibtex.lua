local ok, source = pcall(require, 'blink-bibtex')
if not ok then
  return
end

if source.setup then
  source.setup()
end

local function run_health()
  local ok_health, health = pcall(require, 'blink-bibtex.health')
  if not ok_health then
    if vim and vim.notify then
      vim.notify('blink-bibtex health module is unavailable: ' .. health, vim.log.levels.ERROR, {
        title = 'blink-bibtex',
      })
    end
    return
  end
  health.check()
end

pcall(vim.api.nvim_create_user_command, 'BlinkBibtexHealth', function()
  if vim.fn.exists(':checkhealth') == 2 then
    vim.cmd('checkhealth blink-bibtex')
  else
    run_health()
  end
end, {
  desc = 'Run :checkhealth blink-bibtex for troubleshooting',
})
