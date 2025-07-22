--- Buffer management and cleanup for claudecode.nvim diff operations
local M = {}

local logger = require("claudecode.logger")

--- Register diff autocmds for buffer monitoring
-- @param tab_name string The diff identifier
-- @param new_buffer number Buffer to monitor
-- @param get_autocmd_group function Function to get autocmd group
-- @param resolve_saved function Function to call when diff is saved
-- @param resolve_rejected function Function to call when diff is rejected
-- @return table Array of autocmd IDs
function M.register_diff_autocmds(tab_name, new_buffer, get_autocmd_group, resolve_saved, resolve_rejected)
  local autocmd_ids = {}

  -- Handle :w command to accept diff changes (replaces both BufWritePost and BufWriteCmd)
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      logger.debug("diff", "BufWriteCmd (:w) triggered - accepting diff changes for", tab_name)
      resolve_saved(tab_name, new_buffer)
      -- Prevent actual file write since we're handling it through MCP
      return true
    end,
  })

  -- Buffer deletion monitoring for rejection (multiple events to catch all deletion methods)

  -- BufDelete: When buffer is deleted with :bdelete, :bwipeout, etc.
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufDelete", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      logger.debug("diff", "BufDelete triggered for new buffer", new_buffer, "tab:", tab_name)
      resolve_rejected(tab_name)
    end,
  })

  -- BufUnload: When buffer is unloaded (covers more scenarios)
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufUnload", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      logger.debug("diff", "BufUnload triggered for new buffer", new_buffer, "tab:", tab_name)
      resolve_rejected(tab_name)
    end,
  })

  -- BufWipeout: When buffer is wiped out completely
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufWipeout", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      logger.debug("diff", "BufWipeout triggered for new buffer", new_buffer, "tab:", tab_name)
      resolve_rejected(tab_name)
    end,
  })

  -- Note: We intentionally do NOT monitor old_buffer for deletion
  -- because it's the actual file buffer and shouldn't trigger diff rejection

  return autocmd_ids
end

--- Clean up diff state and associated resources
-- @param tab_name string The diff identifier
-- @param diff_data table Diff data containing buffers, windows, etc.
-- @param active_diffs_table table The active diffs table to update
-- @param reason string Reason for cleanup
function M.cleanup_diff_state(tab_name, diff_data, active_diffs_table, reason)
  if not diff_data then
    return
  end

  -- Clean up autocmds
  for _, autocmd_id in ipairs(diff_data.autocmd_ids or {}) do
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
  end

  -- Clean up unified diff resources
  if diff_data.new_buffer and vim.api.nvim_buf_is_valid(diff_data.new_buffer) then
    local ok, unified_diff = pcall(require, "claudecode.unified_diff")
    if ok then
      pcall(unified_diff.cleanup_unified_diff, diff_data.new_buffer)
    end
  end

  -- Clean up the new buffer (proposed changes)
  if diff_data.new_buffer and vim.api.nvim_buf_is_valid(diff_data.new_buffer) then
    pcall(vim.api.nvim_buf_delete, diff_data.new_buffer, { force = true })
  end

  -- For new files, also clean up the original "(NEW FILE)" buffer
  if diff_data.is_new_file and diff_data.original_buffer and vim.api.nvim_buf_is_valid(diff_data.original_buffer) then
    logger.debug("diff", "Cleaning up (NEW FILE) buffer for new file:", diff_data.old_file_path)
    pcall(vim.api.nvim_buf_delete, diff_data.original_buffer, { force = true })
  end

  -- Close new diff window if still open
  if diff_data.new_window and vim.api.nvim_win_is_valid(diff_data.new_window) then
    pcall(vim.api.nvim_win_close, diff_data.new_window, true)
  end

  -- Turn off diff mode in target window if it still exists
  if diff_data.target_window and vim.api.nvim_win_is_valid(diff_data.target_window) then
    vim.api.nvim_win_call(diff_data.target_window, function()
      vim.cmd("diffoff")
    end)
  end

  -- Remove from active diffs
  active_diffs_table[tab_name] = nil

  logger.debug("diff", "Cleaned up diff state for", tab_name, "due to:", reason)
end

--- Clean up all active diffs
-- @param active_diffs_table table The active diffs table
-- @param cleanup_single_diff function Function to clean up a single diff
-- @param reason string Reason for cleanup
function M.cleanup_all_active_diffs(active_diffs_table, cleanup_single_diff, reason)
  for tab_name, _ in pairs(active_diffs_table) do
    cleanup_single_diff(tab_name, reason)
  end
end

return M