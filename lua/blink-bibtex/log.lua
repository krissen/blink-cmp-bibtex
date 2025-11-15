local config = require('blink-bibtex.config')

local M = {}

local default_levels = (vim.log and vim.log.levels)
  or (vim.lsp and vim.lsp.log_levels)
  or { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

local function inspect(value)
  if type(value) == 'table' and vim.inspect then
    return vim.inspect(value)
  end
  return tostring(value)
end

local function join(parts)
  local formatted = {}
  for idx, part in ipairs(parts) do
    if type(part) == 'string' then
      formatted[idx] = part
    else
      formatted[idx] = inspect(part)
    end
  end
  return table.concat(formatted, ' ')
end

local function emit(level_name, ...)
  local opts = config.get()
  local sink = opts.log
  local level = default_levels[level_name] or default_levels.INFO or 1
  local message = join({ ... })
  if type(sink) ~= 'function' then
    if not vim or not vim.notify then
      return
    end
    sink = function(lvl, msg)
      vim.schedule(function()
        vim.notify(msg, lvl, { title = 'blink-bibtex' })
      end)
    end
  end
  sink(level, string.format('[%s] %s', level_name:lower(), message))
end

function M.debug(...)
  local opts = config.get()
  if not opts.debug then
    return
  end
  emit('DEBUG', ...)
end

function M.info(...)
  emit('INFO', ...)
end

function M.warn(...)
  emit('WARN', ...)
end

function M.error(...)
  emit('ERROR', ...)
end

return M
