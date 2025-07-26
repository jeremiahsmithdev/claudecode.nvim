--- Diff module for Claude Code Neovim integration.
-- Provides native Neovim diff functionality with MCP-compliant blocking operations and state management.
local M = {}

local logger = require("claudecode.logger")

-- Import modular components
local core = require("claudecode.diff.core")
local modes = require("claudecode.diff.modes")
local buffers = require("claudecode.diff.buffers")
local navigation = require("claudecode.diff.navigation")
local blocking = require("claudecode.diff.blocking")

-- Access to active diffs table from core module
local active_diffs = core.get_active_diffs_table()

--- Setup the diff module
-- @param user_diff_config table|nil Reserved for future use
function M.setup(user_diff_config)
  core.setup(user_diff_config)
end

--- Open a diff view between two files
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table Result with provider, tab_name, and success status
function M.open_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  return modes.open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
end

--- Open diff using native Neovim functionality (kept for backward compatibility)
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table Result with provider, tab_name, and success status
function M._open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  return modes.open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
end

--- Register diff state for tracking
-- @param tab_name string Unique identifier for the diff
-- @param diff_data table Diff state data
function M._register_diff_state(tab_name, diff_data)
  active_diffs[tab_name] = diff_data
end

--- Resolve diff as saved (user accepted changes)
-- @param tab_name string The diff identifier
-- @param buffer_id number The buffer that was saved
function M._resolve_diff_as_saved(tab_name, buffer_id)
  local diff_data = active_diffs[tab_name]
  logger.debug("diff", "=== RESOLVE DIFF AS SAVED DEBUG ===")
  logger.debug("diff", "tab_name:", tab_name)
  logger.debug("diff", "buffer_id:", buffer_id)
  logger.debug("diff", "diff_data exists:", diff_data ~= nil)
  if diff_data then
    logger.debug("diff", "diff_data.status:", diff_data.status)
    logger.debug("diff", "diff_data.target_window:", diff_data.target_window, "valid:", diff_data.target_window and vim.api.nvim_win_is_valid(diff_data.target_window))
    logger.debug("diff", "diff_data.original_buffer:", diff_data.original_buffer, "valid:", diff_data.original_buffer and vim.api.nvim_buf_is_valid(diff_data.original_buffer))
    logger.debug("diff", "diff_data.new_buffer:", diff_data.new_buffer, "valid:", diff_data.new_buffer and vim.api.nvim_buf_is_valid(diff_data.new_buffer))
  end
  
  if not diff_data or diff_data.status ~= "pending" then
    logger.debug("diff", "Early return - no diff_data or not pending")
    return
  end

  logger.debug("diff", "Resolving diff as saved for", tab_name, "from buffer", buffer_id)

  -- Capture current cursor position from the diff view for follow_file_changes
  local diff_cursor_pos = nil
  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(current_win) and vim.api.nvim_win_get_buf(current_win) == buffer_id then
    diff_cursor_pos = vim.api.nvim_win_get_cursor(current_win)
  end

  -- Get content from buffer
  local content_lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local final_content = table.concat(content_lines, "\n")
  -- Add trailing newline if the buffer has one
  if #content_lines > 0 and vim.api.nvim_buf_get_option(buffer_id, "eol") then
    final_content = final_content .. "\n"
  end

  -- Create MCP-compliant response
  local result = {
    content = {
      { type = "text", text = "FILE_SAVED" },
      { type = "text", text = final_content },
    },
  }

  diff_data.status = "saved"
  diff_data.result_content = result

  -- Resume the coroutine with the result (for deferred response system)
  if diff_data.resolution_callback then
    logger.debug("diff", "Resuming coroutine for saved diff", tab_name)
    diff_data.resolution_callback(result)
  else
    logger.debug("diff", "No resolution callback found for saved diff", tab_name)
  end

  -- Store navigation info before closing windows
  local current_diff_data = active_diffs[tab_name]
  local original_cursor_pos = current_diff_data and current_diff_data.original_cursor_pos
  local target_file_path = diff_data.old_file_path
  local changed_lines = diff_data.changed_lines

  -- Close diff windows/buffers based on mode
  local state = require("claudecode.state")
  local is_unified = state.state.config and state.state.config.diff_opts and state.state.config.diff_opts.diff_mode == "unified"
  logger.debug("diff", "=== DIFF CLOSING DEBUG ===")
  logger.debug("diff", "is_unified:", is_unified)
  logger.debug("diff", "state.state.config exists:", state.state.config ~= nil)
  if state.state.config then
    logger.debug("diff", "state.state.config.diff_opts exists:", state.state.config.diff_opts ~= nil)
    if state.state.config.diff_opts then
      logger.debug("diff", "diff_mode:", state.state.config.diff_opts.diff_mode)
      logger.debug("diff", "auto_close_on_accept:", state.state.config.diff_opts.auto_close_on_accept)
    end
  end
  
  if is_unified then
    logger.debug("diff", "Processing unified mode diff closing")
    -- In unified mode, we need to close the unified diff buffer and return to original file
    if diff_data.target_window and vim.api.nvim_win_is_valid(diff_data.target_window) then
      logger.debug("diff", "Target window is valid")
      -- Get the current buffer in the target window (should be the unified diff buffer)
      local unified_buf = vim.api.nvim_win_get_buf(diff_data.target_window)
      logger.debug("diff", "Current buffer in target window:", unified_buf)
      
      -- Return to the original file buffer
      if diff_data.original_buffer and vim.api.nvim_buf_is_valid(diff_data.original_buffer) then
        logger.debug("diff", "Setting original buffer", diff_data.original_buffer, "in target window")
        vim.api.nvim_win_set_buf(diff_data.target_window, diff_data.original_buffer)
        logger.debug("diff", "Successfully switched to original buffer")
      else
        logger.debug("diff", "Original buffer is invalid or missing")
      end
      
      -- Delete the unified diff buffer
      if unified_buf and vim.api.nvim_buf_is_valid(unified_buf) and unified_buf ~= diff_data.original_buffer then
        logger.debug("diff", "Deleting unified diff buffer:", unified_buf)
        local delete_success, delete_err = pcall(vim.api.nvim_buf_delete, unified_buf, { force = true })
        logger.debug("diff", "Buffer deletion success:", delete_success, "error:", delete_err)
      else
        logger.debug("diff", "Unified buffer not deleted - invalid or same as original")
      end
    else
      logger.debug("diff", "Target window is invalid")
    end
  else
    logger.debug("diff", "Processing split mode diff closing")
    -- Split mode - close the new window
    if diff_data.new_window and vim.api.nvim_win_is_valid(diff_data.new_window) then
      vim.api.nvim_win_close(diff_data.new_window, true)
    end
    if diff_data.target_window and vim.api.nvim_win_is_valid(diff_data.target_window) then
      vim.api.nvim_set_current_win(diff_data.target_window)
      vim.cmd("diffoff")
    end
  end

  -- Trigger follow_file_changes navigation after closing diff windows
  local follow_file_changes = require("claudecode.follow_file_changes")
  
  -- Use immediate navigation (no delay)
  follow_file_changes.handle_file_change(
    target_file_path,
    diff_cursor_pos or original_cursor_pos,
    original_cursor_pos,
    changed_lines
  )

  -- Always cleanup diff state when resolved through MCP (save_document tool)
  -- The auto_close_on_accept setting only affects manual :w in Neovim
  logger.debug("diff", "Cleaning up diff state after MCP acceptance")
  M._cleanup_diff_state(tab_name, "resolved via MCP save")
end

--- Resolve diff as rejected (user closed/rejected)
-- @param tab_name string The diff identifier
function M._resolve_diff_as_rejected(tab_name)
  local diff_data = active_diffs[tab_name]
  if not diff_data or diff_data.status ~= "pending" then
    return
  end

  -- Create MCP-compliant response
  local result = {
    content = {
      { type = "text", text = "DIFF_REJECTED" },
      { type = "text", text = tab_name },
    },
  }

  diff_data.status = "rejected"
  diff_data.result_content = result

  -- Clean up diff state and resources BEFORE resolving to prevent any interference
  M._cleanup_diff_state(tab_name, "diff rejected")

  -- Use vim.schedule to ensure the resolution callback happens after all cleanup
  vim.schedule(function()
    -- Resume the coroutine with the result (for deferred response system)
    if diff_data.resolution_callback then
      logger.debug("diff", "Resuming coroutine for rejected diff", tab_name)
      diff_data.resolution_callback(result)
    end
  end)
end

--- Register autocmds for a specific diff
-- @param tab_name string The diff identifier
-- @param new_buffer number New file buffer ID
-- @return table List of autocmd IDs
local function register_diff_autocmds(tab_name, new_buffer)
  return buffers.register_diff_autocmds(
    tab_name,
    new_buffer,
    core.get_autocmd_group,
    M._resolve_diff_as_saved,
    M._resolve_diff_as_rejected
  )
end

--- Create diff view from a specific window
-- @param target_window number The window to use as base for the diff
-- @param old_file_path string Path to the original file
-- @param new_buffer number New file buffer ID
-- @param tab_name string The diff identifier
-- @param is_new_file boolean Whether this is a new file (doesn't exist yet)
-- @param existing_buffer number|nil Existing buffer for the file (to avoid E37 error)
-- @return table Info about the created diff layout
function M._create_diff_view_from_window(
  target_window,
  old_file_path,
  new_buffer,
  tab_name,
  is_new_file,
  existing_buffer
)
  return modes.create_diff_view_from_window(
    target_window,
    old_file_path,
    new_buffer,
    tab_name,
    is_new_file,
    existing_buffer
  )
end

--- Clean up diff state and resources
-- @param tab_name string The diff identifier
-- @param reason string Reason for cleanup
function M._cleanup_diff_state(tab_name, reason)
  local diff_data = active_diffs[tab_name]
  buffers.cleanup_diff_state(tab_name, diff_data, active_diffs, reason)
end

--- Clean up all active diffs
-- @param reason string Reason for cleanup
-- NOTE: This will become a public closeAllDiffTabs tool in the future
function M._cleanup_all_active_diffs(reason)
  buffers.cleanup_all_active_diffs(active_diffs, M._cleanup_diff_state, reason)
end

--- Set up blocking diff operation with simpler approach
-- @param params table Parameters for the diff
-- @param resolution_callback function Callback to call when diff resolves
function M._setup_blocking_diff(params, resolution_callback)
  blocking.setup_blocking_diff(
    params,
    resolution_callback,
    M._register_diff_state,
    register_diff_autocmds,
    M._cleanup_diff_state,
    M._create_diff_view_from_window,
    active_diffs
  )
end

--- Blocking diff operation for MCP compliance
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table MCP-compliant response with content array
function M.open_diff_blocking(old_file_path, new_file_path, new_file_contents, tab_name)
  -- Check for existing diff with same tab_name
  if active_diffs[tab_name] then
    -- Resolve the existing diff as rejected before replacing
    M._resolve_diff_as_rejected(tab_name)
  end

  -- Set up blocking diff operation
  local co = coroutine.running()
  if not co then
    error({
      code = -32000,
      message = "Internal server error",
      data = "openDiff must run in coroutine context",
    })
  end

  logger.debug("diff", "Starting diff setup for", tab_name)

  -- Use native diff implementation
  local success, err = pcall(M._setup_blocking_diff, {
    old_file_path = old_file_path,
    new_file_path = new_file_path,
    new_file_contents = new_file_contents,
    tab_name = tab_name,
  }, function(result)
    -- Resume the coroutine with the result
    local resume_success, resume_result = coroutine.resume(co, result)
    if resume_success then
      -- Use the global response sender to avoid module reloading issues
      local co_key = tostring(co)
      if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
        _G.claude_deferred_responses[co_key](resume_result)
        _G.claude_deferred_responses[co_key] = nil
      else
        logger.error("diff", "No global response sender found for coroutine:", co_key)
      end
    else
      logger.error("diff", "Coroutine failed:", tostring(resume_result))
      local co_key = tostring(co)
      if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
        _G.claude_deferred_responses[co_key]({
          error = {
            code = -32603,
            message = "Internal error",
            data = "Coroutine failed: " .. tostring(resume_result),
          },
        })
        _G.claude_deferred_responses[co_key] = nil
      end
    end
  end)

  if not success then
    logger.error("diff", "Diff setup failed for", tab_name, "error:", tostring(err))
    -- If the error is already structured, propagate it directly
    if type(err) == "table" and err.code then
      error(err)
    else
      error({
        code = -32000,
        message = "Error setting up diff",
        data = tostring(err),
      })
    end
  end

  -- Yield and wait indefinitely for user interaction - the resolve functions will resume us
  local user_action_result = coroutine.yield()
  logger.debug("diff", "User action completed for", tab_name)

  -- Return the result directly - this will be sent by the deferred response system
  return user_action_result
end

-- Set up global autocmds for shutdown handling
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = core.get_autocmd_group(),
  callback = function()
    M._cleanup_all_active_diffs("shutdown")
  end,
})

--- Get active diffs table (for internal use by tools)
-- @return table The active diffs table
function M._get_active_diffs()
  return active_diffs
end

--- Mark a diff as externally saved (called by saveDocument tool)
-- @param file_path string Path to the file that was saved
function M._mark_diff_as_externally_saved(file_path)
  local follow_file_changes = require("claudecode.follow_file_changes")
  follow_file_changes.mark_file_as_externally_saved(file_path)

  -- Find diff by file path and mark as saved
  for tab_name, diff_data in pairs(active_diffs) do
    if diff_data.old_file_path == file_path and diff_data.status == "pending" then
      logger.debug("diff", "Found diff to mark as saved:", tab_name)
      diff_data.status = "saved"
      diff_data.externally_saved = true
      break
    end
  end
end

--- Close diff by tab name (used by close_tab tool)
-- @param tab_name string The diff identifier
-- @return boolean success True if diff was found and closed
function M.close_diff_by_tab_name(tab_name)
  return navigation.close_diff_by_tab_name(tab_name, active_diffs, M._cleanup_diff_state, M._resolve_diff_as_rejected)
end

-- Test helper function (only for testing)
function M._get_active_diffs()
  return core.get_active_diffs_table()
end -- Test navigation for fold-aware positioning

-- Manual buffer reload function for testing/debugging
function M.reload_file_buffers_manual(file_path, original_cursor_pos)
  return navigation.reload_file_buffers_manual(file_path, original_cursor_pos)
end

--- Accept the current diff (user command version)
-- This function reads the diff context from buffer variables
function M.accept_current_diff()
  local current_buffer = vim.api.nvim_get_current_buf()
  local tab_name = vim.b[current_buffer].claudecode_diff_tab_name

  if not tab_name then
    vim.notify("No active diff found in current buffer", vim.log.levels.WARN)
    return
  end

  M._resolve_diff_as_saved(tab_name, current_buffer)
end

--- Deny/reject the current diff (user command version)
-- This function reads the diff context from buffer variables
function M.deny_current_diff()
  local current_buffer = vim.api.nvim_get_current_buf()
  local tab_name = vim.b[current_buffer].claudecode_diff_tab_name
  local new_win = vim.b[current_buffer].claudecode_diff_new_win
  local target_window = vim.b[current_buffer].claudecode_diff_target_win

  if not tab_name then
    vim.notify("No active diff found in current buffer", vim.log.levels.WARN)
    return
  end

  -- Close windows and clean up (same logic as the original keymap)
  if new_win and vim.api.nvim_win_is_valid(new_win) then
    vim.api.nvim_win_close(new_win, true)
  end
  if target_window and vim.api.nvim_win_is_valid(target_window) then
    vim.api.nvim_set_current_win(target_window)
    vim.cmd("diffoff")
  end

  M._resolve_diff_as_rejected(tab_name)
end

return M
-- Testing fold-aware navigation with configurable lines_before_fold
