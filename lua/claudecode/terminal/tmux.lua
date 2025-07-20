--- Tmux terminal provider for Claude Code.
-- This provider creates tmux panes to run Claude Code in external tmux sessions.
-- @module claudecode.terminal.tmux

--- @type TerminalProvider
local M = {}

local logger = require("claudecode.logger")

local active_pane_id = nil

local function is_in_tmux()
  return vim and vim.env and vim.env.TMUX ~= nil
end

local function get_tmux_pane_width()
  local handle = io.popen("tmux display-message -p '#{window_width}'")
  if not handle then
    return 80
  end
  local result = handle:read("*a")
  handle:close()
  local cleaned = result and result:gsub("%s+", "") or ""
  return tonumber(cleaned) or 80
end

local function calculate_split_size(percentage)
  if not percentage or percentage <= 0 or percentage >= 1 then
    return nil
  end

  local window_width = get_tmux_pane_width()
  return math.floor(window_width * percentage)
end

local function build_split_command(cmd_string, env_table, effective_config)
  local split_cmd = "tmux split-window"

  if effective_config.split_side == "left" then
    split_cmd = split_cmd .. " -bh"
  else
    split_cmd = split_cmd .. " -h"
  end

  local split_size = calculate_split_size(effective_config.split_width_percentage)
  if split_size then
    split_cmd = split_cmd .. " -l " .. split_size
  end

  -- Just run the command directly - let tmux inherit the full environment naturally
  split_cmd = split_cmd .. " '" .. cmd_string .. "'"

  return split_cmd
end

local function get_active_pane_id()
  if not active_pane_id then
    return nil
  end

  local handle = io.popen("tmux list-panes -F '#{pane_id}' | grep '" .. active_pane_id .. "'")
  if not handle then
    return nil
  end

  local result = handle:read("*a")
  handle:close()

  if result and result:gsub("%s+", "") == active_pane_id then
    return active_pane_id
  end

  active_pane_id = nil
  return nil
end

local function capture_new_pane_id(split_cmd)
  -- Create the pane and get its ID
  local full_cmd = split_cmd .. " \\; display-message -p '#{pane_id}'"
  local handle = io.popen(full_cmd)
  if not handle then
    return nil
  end

  local result = handle:read("*a")
  handle:close()

  local pane_id = result:gsub("%s+", ""):match("%%(%d+)")
  return pane_id and ("%" .. pane_id) or nil
end

function M.setup(term_config)
  if not is_in_tmux() then
    logger.warn("terminal", "Tmux provider configured but not running in tmux session")
    return
  end

  logger.debug("terminal", "Tmux terminal provider configured")
end

function M.open(cmd_string, env_table, effective_config, focus)
  if not is_in_tmux() then
    logger.error("terminal", "Cannot open tmux pane - not in tmux session")
    return
  end

  -- Check if claude is already connected from any source (manual or automatic)
  local claudecode = require("claudecode")
  if claudecode.is_claude_connected() then
    logger.debug("terminal", "Claude is already connected - not creating new tmux pane")
    return
  end

  -- Clean up other lockfiles with current cwd if config option is enabled
  if claudecode.state.config.tmux_cleanup_lockfiles then
    logger.debug("terminal", "tmux_cleanup_lockfiles is enabled, starting lockfile cleanup")
    local lockfile = require("claudecode.lockfile")
    local cleanup_success, cleanup_count, cleanup_error = lockfile.cleanup_lockfiles_with_current_cwd()
    
    if cleanup_success then
      if cleanup_count > 0 then
        logger.info("terminal", "Cleaned up " .. cleanup_count .. " lockfiles with current working directory")
      else
        logger.debug("terminal", "No lockfiles found to clean up")
      end
    else
      logger.warn("terminal", "Failed to cleanup lockfiles: " .. (cleanup_error or "unknown error"))
    end
  end

  if get_active_pane_id() then
    logger.debug("terminal", "Claude tmux pane already exists, focusing existing pane")
    if focus ~= false then
      vim.fn.system("tmux select-pane -t " .. active_pane_id)
    end
    return
  end

  local split_cmd = build_split_command(cmd_string, env_table, effective_config)
  logger.info("terminal", "Creating tmux pane with command: " .. split_cmd)
  logger.info("terminal", "Running claude with inherited tmux environment (no exports)")

  local new_pane_id = capture_new_pane_id(split_cmd)
  if new_pane_id then
    active_pane_id = new_pane_id
    logger.debug("terminal", "Created tmux pane with ID: " .. active_pane_id)

    if focus == false then
      vim.fn.system("tmux last-pane")
    end
  else
    logger.error("terminal", "Failed to create tmux pane")
  end
end

function M.close()
  local pane_id = get_active_pane_id()
  if not pane_id then
    logger.debug("terminal", "No active Claude tmux pane to close")
    return
  end

  vim.fn.system("tmux kill-pane -t " .. pane_id)
  active_pane_id = nil
  logger.debug("terminal", "Closed tmux pane: " .. pane_id)
end

function M.simple_toggle(cmd_string, env_table, effective_config)
  local pane_id = get_active_pane_id()
  if pane_id then
    M.close()
  else
    -- Check if claude is already connected from any source before creating new pane
    local claudecode = require("claudecode")
    if claudecode.is_claude_connected() then
      logger.debug("terminal", "Claude is already connected - not toggling new tmux pane")
      return
    end
    M.open(cmd_string, env_table, effective_config, true)
  end
end

function M.focus_toggle(cmd_string, env_table, effective_config)
  local pane_id = get_active_pane_id()
  if not pane_id then
    -- Check if claude is already connected from any source before creating new pane
    local claudecode = require("claudecode")
    if claudecode.is_claude_connected() then
      logger.debug("terminal", "Claude is already connected - not creating new tmux pane for focus toggle")
      return
    end
    M.open(cmd_string, env_table, effective_config, true)
    return
  end

  local handle = io.popen("tmux display-message -p '#{pane_active}'")
  if not handle then
    return
  end

  local is_active = handle:read("*a"):gsub("%s+", "") == "1"
  handle:close()

  if is_active then
    M.close()
  else
    vim.fn.system("tmux select-pane -t " .. pane_id)
  end
end

function M.toggle(cmd_string, env_table, effective_config)
  M.simple_toggle(cmd_string, env_table, effective_config)
end

function M.get_active_bufnr()
  return nil
end

function M.is_available()
  return is_in_tmux()
end

function M._get_terminal_for_test()
  return {
    pane_id = active_pane_id,
    is_in_tmux = is_in_tmux(),
  }
end

--- Debug function to test tmux pane environment vs manual pane
function M.test_environment()
  if not is_in_tmux() then
    logger.error("terminal", "Not in tmux session")
    return
  end

  -- Create a simple pane that just shows the environment
  local test_cmd =
    "echo '=== ENVIRONMENT TEST ==='; echo 'SHELL='$SHELL; echo 'PATH (first 100 chars):'$PATH | head -c 100; echo; which claude; echo 'Claude location:' $?; env | grep -E '(CLAUDE|IDE|NVIM)'; echo '=== END TEST ==='; read -p 'Press Enter to close...'"

  -- Create pane with test command directly
  local split_cmd = "tmux split-window -h '" .. test_cmd .. "'"

  logger.info("terminal", "Creating test pane: " .. split_cmd)

  local new_pane_id = capture_new_pane_id(split_cmd)
  if new_pane_id then
    logger.info("terminal", "Test pane created with ID: " .. new_pane_id)
  end
end

--- Debug what environment differences exist between manual and automated
function M.debug_environment_difference()
  if not is_in_tmux() then
    logger.error("terminal", "Not in tmux session")
    return
  end

  logger.info("terminal", "Creating environment comparison panes...")

  -- Test what a normal shell pane gets
  local manual_test =
    "echo '=== MANUAL PANE ENVIRONMENT ==='; which claude; echo 'PATH length:' ${#PATH}; echo 'Shell:' $SHELL; echo 'Key vars:'; env | grep -E '(PATH|SHELL|HOME|LANG)' | head -5; echo 'Press Enter...'; read"
  local manual_split = "tmux split-window -h '" .. manual_test .. "'"

  -- Test our current approach
  local auto_test =
    "echo '=== AUTOMATED PANE ENVIRONMENT ==='; which claude; echo 'PATH length:' ${#PATH}; echo 'Shell:' $SHELL; echo 'Key vars:'; env | grep -E '(PATH|SHELL|HOME|LANG)' | head -5; echo 'Claude vars:'; env | grep CLAUDE; echo 'Press Enter...'; read"
  local env_table = {
    ENABLE_IDE_INTEGRATION = "true",
    FORCE_CODE_TERMINAL = "true",
    CLAUDE_CODE_SSE_PORT = "12345",
  }
  local config = { split_side = "right", split_width_percentage = 0.3 }
  local auto_split = build_split_command(auto_test, env_table, config)

  logger.info("terminal", "Manual pane command: " .. manual_split)
  logger.info("terminal", "Auto pane command: " .. auto_split)

  -- Create both panes
  capture_new_pane_id(manual_split)
  vim.defer_fn(function()
    capture_new_pane_id(auto_split)
  end, 1000)
end

return M
