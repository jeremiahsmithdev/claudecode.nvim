--- Claude Code Neovim Integration
--- This plugin integrates Claude Code CLI with Neovim, enabling
--- seamless AI-assisted coding experiences directly in Neovim.

local M = {}

local logger = require("claudecode.logger")
local state = require("claudecode.state")

-- Re-export version information from the original location
--- @class ClaudeCode.Version
--- @field major integer Major version number
--- @field minor integer Minor version number
--- @field patch integer Patch version number
--- @field prerelease string|nil Prerelease identifier (e.g., "alpha", "beta")
--- @field string fun(self: ClaudeCode.Version):string Returns the formatted version string

--- The current version of the plugin.
--- @type ClaudeCode.Version
M.version = {
  major = 0,
  minor = 2,
  patch = 0,
  prerelease = nil,
}

function M.version:string()
  local version_str = self.major .. "." .. self.minor .. "." .. self.patch
  if self.prerelease then
    version_str = version_str .. "-" .. self.prerelease
  end
  return version_str
end

-- Re-export state for backward compatibility
M.state = state.state

-- Re-export core state functions
M.is_claude_connected = state.is_claude_connected

--- Send @ mention to Claude Code, handling connection state automatically
--- @param file_path string The file path to send
--- @param start_line number|nil Start line (0-indexed for Claude)
--- @param end_line number|nil End line (0-indexed for Claude)
--- @param context string|nil Context for logging
--- @return boolean success Whether the operation was successful
--- @return string|nil error Error message if failed
function M.send_at_mention(file_path, start_line, end_line, context)
  context = context or "command"

  if not M.state.server then
    logger.error(context, "Claude Code integration is not running")
    return false, "Claude Code integration is not running"
  end

  -- Check if Claude Code is connected
  if M.is_claude_connected() then
    -- Claude is connected, send immediately and ensure terminal is visible
    local success, error_msg = M._broadcast_at_mention(file_path, start_line, end_line)
    if success then
      local terminal = require("claudecode.terminal")
      if not terminal.is_external_provider() then
        terminal.ensure_visible()
      end
    end
    return success, error_msg
  else
    -- Claude not connected, queue the mention
    state._queue_at_mention({
      file_path = file_path,
      start_line = start_line,
      end_line = end_line,
      context = context,
    })

    local terminal = require("claudecode.terminal")
    if terminal.is_external_provider() then
      logger.debug(context, "Queued @ mention for external Claude Code instance: " .. file_path)
    else
      terminal.open()
      logger.debug(context, "Queued @ mention and launched Claude Code: " .. file_path)
    end

    return true, nil
  end
end

--- Set up the plugin with user configuration
--- @param opts table|nil Optional configuration table to override defaults.
--- @return table The plugin module
function M.setup(opts)
  opts = opts or {}

  local terminal_opts = nil
  if opts.terminal then
    terminal_opts = opts.terminal
    opts.terminal = nil -- Remove from main opts to avoid polluting state.config
  end

  -- Initialize state with user config
  state.initialize(opts)

  logger.setup(M.state.config)

  -- Setup terminal module
  local terminal_setup_ok, terminal_module = pcall(require, "claudecode.terminal")
  if terminal_setup_ok then
    if type(terminal_module.setup) == "function" then
      terminal_module.setup(terminal_opts, M.state.config.terminal_cmd)
    end
  else
    logger.error("init", "Failed to load claudecode.terminal module for setup.")
  end

  local diff = require("claudecode.diff")
  diff.setup(M.state.config)

  if M.state.config.auto_start then
    M.start(false) -- Suppress notification on auto-start
  end

  -- Setup user commands
  local commands = require("claudecode.commands")
  commands.setup()

  -- Setup cleanup autocmd
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ClaudeCodeShutdown", { clear = true }),
    callback = function()
      if M.state.server then
        M.stop()
      else
        state._clear_mention_queue()
      end
    end,
    desc = "Automatically stop Claude Code integration when exiting Neovim",
  })

  return M
end

--- Start the Claude Code integration
--- @param show_startup_notification? boolean Whether to show a notification upon successful startup (defaults to true)
--- @return boolean success Whether the operation was successful
--- @return number|string port_or_error The WebSocket port if successful, or error message if failed
function M.start(show_startup_notification)
  if show_startup_notification == nil then
    show_startup_notification = true
  end

  if M.state.server then
    local msg = "Claude Code integration is already running on port " .. tostring(M.state.port)
    logger.warn("init", msg)
    return false, "Already running"
  end

  local server = require("claudecode.server.init")
  local lockfile = require("claudecode.lockfile")

  -- Check if a lockfile already exists for this Neovim instance
  local existing_lockfile, existing_port = lockfile.get_lockfile_for_current_pid()

  if existing_lockfile then
    logger.debug("init", "Found existing lockfile for current PID at port " .. existing_port)

    local token_success, existing_auth_token, token_error = lockfile.get_auth_token(existing_port)
    if token_success and existing_auth_token then
      M.state.port = existing_port
      M.state.auth_token = existing_auth_token

      local success, result = server.start(M.state.config, existing_auth_token)
      if success then
        M.state.server = server
        logger.debug("init", "Reusing existing lockfile and started server on port " .. existing_port)
      else
        logger.warn(
          "init",
          "Failed to start server with existing lockfile, creating new setup: " .. (result or "unknown error")
        )
        existing_lockfile = false
      end
    else
      logger.warn("init", "Could not read auth token from existing lockfile: " .. (token_error or "unknown error"))
      existing_lockfile = false
    end
  end

  local auth_token

  if not existing_lockfile then
    -- Generate auth token
    local auth_success, auth_result = pcall(function()
      return lockfile.generate_auth_token()
    end)

    if not auth_success then
      local error_msg = "Failed to generate authentication token: " .. (auth_result or "unknown error")
      logger.error("init", error_msg)
      return false, error_msg
    end

    auth_token = auth_result

    if not auth_token or type(auth_token) ~= "string" or #auth_token < 10 then
      local error_msg = "Invalid authentication token generated"
      logger.error("init", error_msg)
      return false, error_msg
    end

    local success, result = server.start(M.state.config, auth_token)

    if not success then
      local error_msg = "Failed to start Claude Code server: " .. (result or "unknown error")
      logger.error("init", error_msg)
      return false, error_msg
    end

    M.state.server = server
    M.state.port = tonumber(result)
    M.state.auth_token = auth_token

    local lock_success, lock_result = lockfile.create(M.state.port, auth_token)
    if not lock_success then
      logger.warn("init", "Failed to create lockfile: " .. (lock_result or "unknown error"))
    end
  end

  -- Set up connection handling
  local selection = require("claudecode.selection")
  if M.state.config.track_selection then
    selection.enable(server)
  end

  -- Client connection handling is already built into server.start() via callbacks
  -- The server notifies this module about connections via _process_queued_mentions

  if show_startup_notification then
    logger.info("init", "Claude Code integration started on port " .. tostring(M.state.port))
  end

  return true, M.state.port
end

--- Stop the Claude Code integration
--- @return boolean success Whether the operation was successful
--- @return string? error Error message if operation failed
function M.stop()
  if not M.state.server then
    logger.warn("init", "Claude Code integration is not running")
    return false, "Not running"
  end

  local server = require("claudecode.server")
  local selection = require("claudecode.selection")

  selection.disable()
  server.stop()
  state.reset()

  logger.info("init", "Claude Code integration stopped")
  return true, nil
end

--- Get version information
--- @return table Version information
function M.get_version()
  return {
    version = M.version:string(),
    major = M.version.major,
    minor = M.version.minor,
    patch = M.version.patch,
    prerelease = M.version.prerelease,
  }
end

--- Get the current plugin configuration
--- @return table The current configuration
function M.get_config()
  return state.get_config()
end

--- Navigate to a file after Claude makes changes (for follow_file_changes feature)
--- @param file_path string Path to the file to navigate to
--- @param cursor_pos table|nil Optional cursor position {row, col}
function M.navigate_to_file_after_change(file_path, cursor_pos)
  local follow_file_changes = require("claudecode.follow_file_changes")
  follow_file_changes.navigate_to_file_after_change(file_path, cursor_pos)
end

-- Internal helper functions that need to be accessible to other modules
function M._broadcast_at_mention(file_path, start_line, end_line)
  local server = require("claudecode.server")
  local formatted_path, is_directory = M._format_path_for_at_mention(file_path)

  local mention_data = {
    type = "at_mention",
    file_path = formatted_path,
    start_line = start_line,
    end_line = end_line,
    is_directory = is_directory,
  }

  return server.send_message(mention_data)
end

function M._format_path_for_at_mention(file_path)
  local expanded_path = vim.fn.expand(file_path)
  local is_directory = vim.fn.isdirectory(expanded_path) == 1

  if is_directory then
    return expanded_path, true
  else
    return expanded_path, false
  end
end

function M._add_paths_to_claude(file_paths, options)
  options = options or {}
  local context = options.context or "file_add"

  if not M.state.server then
    logger.error(context, "Claude Code integration is not running")
    return false
  end

  for _, file_path in ipairs(file_paths) do
    local success, error_msg = M.send_at_mention(file_path, nil, nil, context)
    if not success then
      logger.error(context, "Failed to add " .. file_path .. ": " .. (error_msg or "unknown error"))
    else
      logger.debug(context, "Added to Claude: " .. file_path)
    end
  end

  return true
end

-- Expose internal state management for testing
M._process_queued_mentions = state.process_queued_mentions
M._ensure_terminal_visible_if_connected = state.ensure_terminal_visible_if_connected

return M
