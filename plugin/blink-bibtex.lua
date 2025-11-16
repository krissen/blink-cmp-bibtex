local ok, source = pcall(require, 'blink-bibtex')
if not ok then
  return
end

if type(source.setup) == 'function' then
  source.setup()
end
