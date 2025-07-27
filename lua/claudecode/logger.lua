---@brief Centralized logger for Claude Code Neovim integration.
-- Provides level-based logging in a structured JSON format for file logs.
local M = {}

M.levels = {
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  DEBUG = 4,
  TRACE = 5,
}

local level_values = {
  error = M.levels.ERROR,
  warn = M.levels.WARN,
  info = M.levels.INFO,
  debug = M.levels.DEBUG,
  trace = M.levels.TRACE,
}

local level_names = {
  [M.levels.ERROR] = "ERROR",
  [M.levels.WARN] = "WARN",
  [M.levels.INFO] = "INFO",
  [M.levels.DEBUG] = "DEBUG",
  [M.levels.TRACE] = "TRACE",
}

local current_log_level_value = M.levels.INFO
local current_notify_log_level_value = M.levels.INFO
local log_file_path = nil
local log_to_file = false

--- @param plugin_config table The configuration table (e.g., from claudecode.init.state.config).
function M.setup(plugin_config)
  local conf = plugin_config

  -- Set file log level
  current_log_level_value = (conf and conf.log_level and level_values[conf.log_level]) or M.levels.INFO

  -- Set notify log level (defaults to same as log_level if not specified)
  current_notify_log_level_value = (conf and conf.notify_log_level and level_values[conf.notify_log_level])
    or current_log_level_value

  -- Set up file logging
  log_file_path = vim.fn.stdpath("cache") .. "/claudecode.log"
  log_to_file = true

  -- Clear log file on setup (truncate for new session)
  local file = io.open(log_file_path, "w")
  if file then
    file:close()
  end
end

local function log(level, component, message_parts)
  -- Skip if level is higher than both file and notify levels
  if level > current_log_level_value and level > current_notify_log_level_value then
    return
  end

  local level_name = level_names[level] or "UNKNOWN"

  local message = ""
  for i, part in ipairs(message_parts) do
    if i > 1 then
      message = message .. " "
    end
    if type(part) == "table" or type(part) == "boolean" then
      message = message .. vim.inspect(part)
    else
      message = message .. tostring(part)
    end
  end

  -- Write to file if level meets file log threshold
  if log_to_file and log_file_path and level <= current_log_level_value then
    local source_info = {}
    for stack_level = 2, 6 do
      local info = debug.getinfo(stack_level, "Sl")
      if info and info.source and info.currentline then
        local file_path = info.source:gsub("^@", "") -- Remove @ prefix
        if not file_path:match("/logger%.lua$") then
          if file_path:find("/claudecode.nvim/") then
            file_path = "./" .. file_path:match(".*/claudecode.nvim/(.*)")
          end
          source_info = { file = file_path, line = info.currentline }
          break
        end
      end
    end

    local log_entry = {
      level = level_name,
      component = component,
      source = source_info,
      timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      message = message,
    }
    local json_message = vim.json.encode(log_entry)
    local file = io.open(log_file_path, "a")
    if file then
      file:write(json_message .. "\n")
      file:close()
    end
  end

  -- Send notifications if level meets notify threshold
  if level <= current_notify_log_level_value then
    local prefix = "[ClaudeCode]"
    if component then
      prefix = prefix .. " [" .. component .. "]"
    end
    prefix = prefix .. " [" .. level_name .. "]"

    if level == M.levels.ERROR then
      vim.schedule(function()
        vim.notify(prefix .. " " .. message, vim.log.levels.ERROR, { title = "ClaudeCode Error" })
      end)
    elseif level == M.levels.WARN then
      vim.schedule(function()
        vim.notify(prefix .. " " .. message, vim.log.levels.WARN, { title = "ClaudeCode Warning" })
      end)
    else
      -- For INFO, DEBUG, TRACE, use nvim_echo to avoid flooding notifications,
      -- to make them appear in :messages, and wrap in vim.schedule
      -- to avoid "nvim_echo must not be called in a fast event context".
      vim.schedule(function()
        vim.api.nvim_echo({ { prefix .. " " .. message, "Normal" } }, true, {})
      end)
    end
  end
end

--- @param component string|nil Optional component/module name.
-- @param ... any Varargs representing parts of the message.
function M.error(component, ...)
  if type(component) ~= "string" then
    log(M.levels.ERROR, nil, { component, ... })
  else
    log(M.levels.ERROR, component, { ... })
  end
end

--- @param component string|nil Optional component/module name.
-- @param ... any Varargs representing parts of the message.
function M.warn(component, ...)
  if type(component) ~= "string" then
    log(M.levels.WARN, nil, { component, ... })
  else
    log(M.levels.WARN, component, { ... })
  end
end

--- @param component string|nil Optional component/module name.
-- @param ... any Varargs representing parts of the message.
function M.info(component, ...)
  if type(component) ~= "string" then
    log(M.levels.INFO, nil, { component, ... })
  else
    log(M.levels.INFO, component, { ... })
  end
end

--- Check if a specific log level is enabled
-- @param level_name string The level name ("error", "warn", "info", "debug", "trace")
-- @return boolean Whether the level is enabled
function M.is_level_enabled(level_name)
  local level_value = level_values[level_name]
  if not level_value then
    return false
  end
  return level_value <= current_log_level_value
end

--- @param component string|nil Optional component/module name.
-- @param ... any Varargs representing parts of the message.
function M.debug(component, ...)
  if type(component) ~= "string" then
    log(M.levels.DEBUG, nil, { component, ... })
  else
    log(M.levels.DEBUG, component, { ... })
  end
end

--- @param component string|nil Optional component/module name.
-- @param ... any Varargs representing parts of the message.
function M.trace(component, ...)
  if type(component) ~= "string" then
    log(M.levels.TRACE, nil, { component, ... })
  else
    log(M.levels.TRACE, component, { ... })
  end
end

--- Get the log file path
-- @return string|nil The log file path
function M.get_log_file_path()
  return log_file_path
end

local default_config_for_initial_setup = require("claudecode.config").defaults
M.setup(default_config_for_initial_setup)

return M