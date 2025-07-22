---@brief [[
--- Lock file management for Claude Code Neovim integration.
--- This module handles creation, removal and updating of lock files
--- which allow Claude Code CLI to discover the Neovim integration.
---@brief ]]

local M = {}

--- Path to the lock file directory
---@return string lock_dir The path to the lock file directory
local function get_lock_dir()
  local claude_config_dir = os.getenv("CLAUDE_CONFIG_DIR")
  if claude_config_dir and claude_config_dir ~= "" then
    return vim.fn.expand(claude_config_dir .. "/ide")
  else
    return vim.fn.expand("~/.claude/ide")
  end
end

M.lock_dir = get_lock_dir()

-- Track if random seed has been initialized
local random_initialized = false

--- Generate a random UUID for authentication
---@return string uuid A randomly generated UUID string
local function generate_auth_token()
  -- Initialize random seed only once
  if not random_initialized then
    local seed = os.time() + vim.fn.getpid()
    -- Add more entropy if available
    if vim.loop and vim.loop.hrtime then
      seed = seed + (vim.loop.hrtime() % 1000000)
    end
    math.randomseed(seed)

    -- Call math.random a few times to "warm up" the generator
    for _ = 1, 10 do
      math.random()
    end
    random_initialized = true
  end

  -- Generate UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  local uuid = template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end)

  -- Validate generated UUID format
  if not uuid:match("^[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+$") then
    error("Generated invalid UUID format: " .. uuid)
  end

  if #uuid ~= 36 then
    error("Generated UUID has invalid length: " .. #uuid .. " (expected 36)")
  end

  return uuid
end

--- Generate a new authentication token
---@return string auth_token A newly generated authentication token
function M.generate_auth_token()
  return generate_auth_token()
end

--- Create the lock file for a specified WebSocket port
---@param port number The port number for the WebSocket server
---@param auth_token string|nil Optional pre-generated auth token (generates new one if not provided)
---@return boolean success Whether the operation was successful
---@return string result_or_error The lock file path if successful, or error message if failed
---@return string? auth_token The authentication token if successful
function M.create(port, auth_token)
  if not port or type(port) ~= "number" then
    return false, "Invalid port number"
  end

  if port < 1 or port > 65535 then
    return false, "Port number out of valid range (1-65535): " .. tostring(port)
  end

  local ok, err = pcall(function()
    return vim.fn.mkdir(M.lock_dir, "p")
  end)

  if not ok then
    return false, "Failed to create lock directory: " .. (err or "unknown error")
  end

  local lock_path = M.lock_dir .. "/" .. port .. ".lock"

  local workspace_folders = M.get_workspace_folders()
  if not auth_token then
    local auth_success, auth_result = pcall(generate_auth_token)
    if not auth_success then
      return false, "Failed to generate authentication token: " .. (auth_result or "unknown error")
    end
    auth_token = auth_result
  else
    -- Validate provided auth_token
    if type(auth_token) ~= "string" then
      return false, "Authentication token must be a string, got " .. type(auth_token)
    end
    if #auth_token < 10 then
      return false, "Authentication token too short (minimum 10 characters)"
    end
    if #auth_token > 500 then
      return false, "Authentication token too long (maximum 500 characters)"
    end
  end

  -- Prepare lock file content
  local lock_content = {
    pid = vim.fn.getpid(),
    workspaceFolders = workspace_folders,
    ideName = "Neovim",
    transport = "ws",
    authToken = auth_token,
  }

  local json
  local ok_json, json_err = pcall(function()
    json = vim.json.encode(lock_content)
    return json
  end)

  if not ok_json or not json then
    return false, "Failed to encode lock file content: " .. (json_err or "unknown error")
  end

  local file = io.open(lock_path, "w")
  if not file then
    return false, "Failed to create lock file: " .. lock_path
  end

  local write_ok, write_err = pcall(function()
    file:write(json)
    file:close()
  end)

  if not write_ok then
    pcall(function()
      file:close()
    end)
    return false, "Failed to write lock file: " .. (write_err or "unknown error")
  end

  return true, lock_path, auth_token
end

--- Remove the lock file for the given port
---@param port number The port number of the WebSocket server
---@return boolean success Whether the operation was successful
---@return string? error Error message if operation failed
function M.remove(port)
  if not port or type(port) ~= "number" then
    return false, "Invalid port number"
  end

  local lock_path = M.lock_dir .. "/" .. port .. ".lock"

  if vim.fn.filereadable(lock_path) == 0 then
    return false, "Lock file does not exist: " .. lock_path
  end

  local ok, err = pcall(function()
    return os.remove(lock_path)
  end)

  if not ok then
    return false, "Failed to remove lock file: " .. (err or "unknown error")
  end

  return true
end

--- Update the lock file for the given port
---@param port number The port number of the WebSocket server
---@return boolean success Whether the operation was successful
---@return string result_or_error The lock file path if successful, or error message if failed
---@return string? auth_token The authentication token if successful
function M.update(port)
  if not port or type(port) ~= "number" then
    return false, "Invalid port number"
  end

  local exists = vim.fn.filereadable(M.lock_dir .. "/" .. port .. ".lock") == 1
  if exists then
    local remove_ok, remove_err = M.remove(port)
    if not remove_ok then
      return false, "Failed to update lock file: " .. remove_err
    end
  end

  return M.create(port)
end

--- Read the authentication token from a lock file
---@param port number The port number of the WebSocket server
---@return boolean success Whether the operation was successful
---@return string? auth_token The authentication token if successful, or nil if failed
---@return string? error Error message if operation failed
function M.get_auth_token(port)
  if not port or type(port) ~= "number" then
    return false, nil, "Invalid port number"
  end

  local lock_path = M.lock_dir .. "/" .. port .. ".lock"

  if vim.fn.filereadable(lock_path) == 0 then
    return false, nil, "Lock file does not exist: " .. lock_path
  end

  local file = io.open(lock_path, "r")
  if not file then
    return false, nil, "Failed to open lock file: " .. lock_path
  end

  local content = file:read("*all")
  file:close()

  if not content or content == "" then
    return false, nil, "Lock file is empty: " .. lock_path
  end

  local ok, lock_data = pcall(vim.json.decode, content)
  if not ok or type(lock_data) ~= "table" then
    return false, nil, "Failed to parse lock file JSON: " .. lock_path
  end

  local auth_token = lock_data.authToken
  if not auth_token or type(auth_token) ~= "string" then
    return false, nil, "No valid auth token found in lock file"
  end

  return true, auth_token, nil
end

--- Get active LSP clients using available API
---@return table Array of LSP clients
local function get_lsp_clients()
  if vim.lsp then
    if vim.lsp.get_clients then
      -- Neovim >= 0.11
      return vim.lsp.get_clients()
    elseif vim.lsp.get_active_clients then
      -- Neovim 0.8-0.10
      return vim.lsp.get_active_clients()
    end
  end
  return {}
end

--- Get workspace folders for the lock file
---@return table Array of workspace folder paths
function M.get_workspace_folders()
  local folders = {}

  -- Add current working directory
  table.insert(folders, vim.fn.getcwd())

  -- Get LSP workspace folders if available
  local clients = get_lsp_clients()
  for _, client in pairs(clients) do
    if client.config and client.config.workspace_folders then
      for _, ws in ipairs(client.config.workspace_folders) do
        -- Convert URI to path
        local path = ws.uri
        if path:sub(1, 7) == "file://" then
          path = path:sub(8)
        end

        -- Check if already in the list
        local exists = false
        for _, folder in ipairs(folders) do
          if folder == path then
            exists = true
            break
          end
        end

        if not exists then
          table.insert(folders, path)
        end
      end
    end
  end

  return folders
end

--- Clean up lockfiles that contain the current working directory in their workspace folders
---@return boolean success Whether the operation was successful
---@return number count Number of lockfiles cleaned up
---@return string? error Error message if operation failed
function M.cleanup_lockfiles_with_current_cwd()
  local logger = require("claudecode.logger")
  local current_cwd = vim.fn.getcwd()
  local current_pid = vim.fn.getpid()
  local cleaned_count = 0
  local errors = {}

  logger.debug("lockfile", "Starting lockfile cleanup for current working directory: " .. current_cwd)
  logger.debug("lockfile", "Current Neovim PID: " .. current_pid .. " (will be skipped)")

  -- Check if lock directory exists
  if vim.fn.isdirectory(M.lock_dir) == 0 then
    return true, 0, nil -- No lock directory means nothing to clean
  end

  -- Get all .lock files in the directory
  local lock_files = vim.fn.glob(M.lock_dir .. "/*.lock", false, true)

  for _, lock_path in ipairs(lock_files) do
    -- Try to read and parse the lockfile
    local file = io.open(lock_path, "r")
    if file then
      local content = file:read("*all")
      file:close()

      if content and content ~= "" then
        local ok, lock_data = pcall(vim.json.decode, content)
        if ok and type(lock_data) == "table" and lock_data.workspaceFolders then
          -- Skip if this is the current Neovim instance's lockfile
          if lock_data.pid and lock_data.pid == current_pid then
            logger.debug("lockfile", "Skipping current instance lockfile: " .. lock_path)
          else
            -- Check if current cwd is in workspace folders
            for _, workspace_path in ipairs(lock_data.workspaceFolders) do
              if workspace_path == current_cwd then
                -- Delete this lockfile
                local remove_ok, remove_err = pcall(function()
                  return os.remove(lock_path)
                end)

                if remove_ok then
                  cleaned_count = cleaned_count + 1
                  logger.debug(
                    "lockfile",
                    "Removed lockfile with matching workspace (PID "
                      .. (lock_data.pid or "unknown")
                      .. "): "
                      .. lock_path
                  )
                  break -- Found match, no need to check other workspace folders
                else
                  local error_msg = "Failed to remove " .. lock_path .. ": " .. (remove_err or "unknown error")
                  logger.error("lockfile", error_msg)
                  table.insert(errors, error_msg)
                end
              end
            end
          end
        end
      end
    else
      local error_msg = "Failed to read " .. lock_path
      logger.error("lockfile", error_msg)
      table.insert(errors, error_msg)
    end
  end

  if cleaned_count > 0 then
    logger.debug("lockfile", "Lockfile cleanup completed. Cleaned " .. cleaned_count .. " lockfiles")
  end

  if #errors > 0 then
    return false, cleaned_count, table.concat(errors, "; ")
  end

  return true, cleaned_count, nil
end

--- Check if a lockfile exists for the current Neovim instance (by PID)
---@return boolean exists Whether a lockfile exists for current PID
---@return number|nil port The port number if lockfile exists, nil otherwise
---@return string|nil lockfile_path The path to the existing lockfile, nil otherwise
function M.get_lockfile_for_current_pid()
  local current_pid = vim.fn.getpid()

  -- Check if lock directory exists
  if vim.fn.isdirectory(M.lock_dir) == 0 then
    return false, nil, nil
  end

  -- Get all .lock files in the directory
  local lock_files = vim.fn.glob(M.lock_dir .. "/*.lock", false, true)

  for _, lock_path in ipairs(lock_files) do
    -- Try to read and parse the lockfile
    local file = io.open(lock_path, "r")
    if file then
      local content = file:read("*all")
      file:close()

      if content and content ~= "" then
        local ok, lock_data = pcall(vim.json.decode, content)
        if ok and type(lock_data) == "table" and lock_data.pid == current_pid then
          -- Extract port from filename (e.g., "12345.lock" -> 12345)
          local port = lock_path:match("/(%d+)%.lock$")
          if port then
            return true, tonumber(port), lock_path
          end
        end
      end
    end
  end

  return false, nil, nil
end

return M
