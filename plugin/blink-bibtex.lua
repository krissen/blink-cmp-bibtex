if not pcall(require, 'blink.cmp') then
  return
end

local ok, source = pcall(require, 'blink-bibtex')
if not ok then
  return
end

source.setup()
