--- State management for Claude Code Neovim integration.
-- Centralizes all plugin state and state-related operations.
local M = {}

local config = require("claudecode.config")

--- @class ClaudeCode.State
--- @field config ClaudeCode.Config The current plugin configuration.
--- @field server table|nil The WebSocket server instance.
--- @field port number|nil The port the server is running on.
--- @field auth_token string|nil The authentication token for the current session.
--- @field initialized boolean Whether the plugin has been initialized.
--- @field queued_mentions table[] Array of queued @ mentions waiting for connection.
--- @field connection_timer table|nil Timer for connection timeout.

--- The global plugin state
--- @type ClaudeCode.State
M.state = {
  config = vim.tbl_deep_extend("force", {}, config.defaults),
  server = nil,
  port = nil,
  auth_token = nil,
  initialized = false,
  queued_mentions = {},
  connection_timer = nil,
}

--- Check if Claude Code is connected to WebSocket server
--- @return boolean connected Whether Claude Code has active connections
function M.is_claude_connected()
  local logger = require("claudecode.logger")

  if not M.state.port then
    logger.info("state", "is_claude_connected: No port set, returning false")
    return false
  end

  logger.info("state", "is_claude_connected: Port set to", M.state.port)

  local server = require("claudecode.server.init")
  local status = server.get_status()
  local is_connected = status.running and status.client_count > 0

  logger.info("state", "is_claude_connected: server status", vim.inspect(status))
  logger.info("state", "is_claude_connected: returning", is_connected)

  return is_connected
end

--- Clear the @ mention queue and stop timers
local function clear_mention_queue()
  M.state.queued_mentions = {}

  if M.state.connection_timer then
    M.state.connection_timer:stop()
    M.state.connection_timer:close()
    M.state.connection_timer = nil
  end
end

--- Add @ mention to queue for later sending
--- @param mention_data table The @ mention data to queue
local function queue_at_mention(mention_data)
  table.insert(M.state.queued_mentions, {
    data = mention_data,
    timestamp = vim.fn.localtime(),
  })

  -- Set up connection timer if not already active
  if not M.state.connection_timer then
    M.state.connection_timer = vim.defer_fn(function()
      local logger = require("claudecode.logger")
      local config_timeout = M.state.config.connection_timeout or 10000
      logger.warn("state", "Connection timeout reached (" .. config_timeout .. "ms), clearing queued @ mentions")
      clear_mention_queue()
    end, M.state.config.connection_timeout or 10000)
  end
end

--- Process queued @ mentions after connection established
function M.process_queued_mentions()
  local logger = require("claudecode.logger")

  if #M.state.queued_mentions == 0 then
    return
  end

  local current_time = vim.fn.localtime()
  local timeout = M.state.config.queue_timeout or 5000

  -- Filter out expired mentions
  local valid_mentions = {}
  for _, queued in ipairs(M.state.queued_mentions) do
    if (current_time - queued.timestamp) * 1000 < timeout then
      table.insert(valid_mentions, queued)
    else
      logger.debug("state", "Discarding expired @ mention")
    end
  end

  logger.info("state", "Processing " .. #valid_mentions .. " queued @ mentions")

  for _, queued in ipairs(valid_mentions) do
    vim.schedule(function()
      local server = require("claudecode.server.init")
      local success = server.send_message(queued.data)
      if not success then
        logger.error("state", "Failed to send queued @ mention")
      end
    end)
  end

  clear_mention_queue()

  -- Small delay to ensure messages are processed before showing terminal
  vim.defer_fn(function()
    M.ensure_terminal_visible_if_connected()
  end, M.state.config.connection_wait_delay or 200)
end

--- Show terminal if Claude is connected and it's not already visible
--- @return boolean success Whether terminal was shown or was already visible
function M.ensure_terminal_visible_if_connected()
  if not M.is_claude_connected() then
    return false
  end

  local terminal = require("claudecode.terminal")
  if terminal.is_open() then
    return true -- Already visible
  end

  terminal.open()
  return true
end

--- Initialize state with user configuration
--- @param user_config table|nil User configuration to merge with defaults
function M.initialize(user_config)
  if user_config then
    M.state.config = config.apply(user_config)
  else
    M.state.config = config.apply()
  end

  M.state.initialized = true
end

--- Reset state to initial values
function M.reset()
  clear_mention_queue()

  M.state = {
    config = vim.tbl_deep_extend("force", {}, config.defaults),
    server = nil,
    port = nil,
    auth_token = nil,
    initialized = false,
    queued_mentions = {},
    connection_timer = nil,
  }
end

--- Get the current plugin configuration
--- @return ClaudeCode.Config The current configuration
function M.get_config()
  return M.state.config
end

--- Export private functions for testing
M._queue_at_mention = queue_at_mention
M._clear_mention_queue = clear_mention_queue

return M
