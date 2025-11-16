local ok, source = pcall(require, 'blink-cmp-bibtex')
if not ok then
  return
end

if type(source.setup) == 'function' then
  source.setup()
end
