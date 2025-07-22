--- Navigation and file changes handling for claudecode.nvim diff operations
local M = {}

local logger = require("claudecode.logger")

--- Mark diff as externally saved via saveDocument tool
-- @param file_path string Path to the file that was saved
-- @param active_diffs_table table The active diffs table to update
function M.mark_diff_as_externally_saved(file_path, active_diffs_table)
  local follow_file_changes = require("claudecode.follow_file_changes")
  follow_file_changes.mark_file_as_externally_saved(file_path)

  -- Find diff by file path and mark as saved
  for tab_name, diff_data in pairs(active_diffs_table) do
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
-- @param active_diffs_table table The active diffs table
-- @param cleanup_diff_state function Function to clean up diff state
-- @param resolve_rejected function Function to resolve diff as rejected
-- @return boolean success True if diff was found and closed
function M.close_diff_by_tab_name(tab_name, active_diffs_table, cleanup_diff_state, resolve_rejected)
  local diff_data = active_diffs_table[tab_name]
  if not diff_data then
    return false
  end

  -- If the diff was already saved, handle file changes immediately
  if diff_data.status == "saved" then
    -- Claude Code CLI has written the file
    if diff_data.old_file_path then
      local follow_file_changes = require("claudecode.follow_file_changes")
      follow_file_changes.handle_file_change(
        diff_data.old_file_path,
        diff_data.original_cursor_pos,
        diff_data.original_cursor_pos
      )
    end
    cleanup_diff_state(tab_name, "diff tab closed after save")
    return true
  end

  -- If still pending, check if Claude has already marked it as saved via saveDocument
  if diff_data.status == "pending" then
    local follow_file_changes = require("claudecode.follow_file_changes")

    -- Check if the diff was already marked as externally saved by saveDocument
    if follow_file_changes.check_and_clear_external_save_flag(diff_data.old_file_path) then
      logger.debug(
        "diff",
        "Diff was already marked as externally saved - treating as accepted",
        diff_data.old_file_path
      )
      diff_data.status = "saved"

      -- Get cursor position from diff view if available
      local cursor_pos = diff_data.original_cursor_pos
      if diff_data.new_window and vim.api.nvim_win_is_valid(diff_data.new_window) then
        cursor_pos = vim.api.nvim_win_get_cursor(diff_data.new_window)
      end

      -- Handle file change immediately (no delay)
      follow_file_changes.handle_file_change(diff_data.old_file_path, cursor_pos, diff_data.original_cursor_pos)

      cleanup_diff_state(tab_name, "diff tab closed after external save via saveDocument")
      return true
    end

    -- No external save flag set - check file modification as fallback
    logger.debug("diff", "No external save flag set - checking file modification as fallback")

    -- Get cursor position from diff view if available
    local cursor_pos = diff_data.original_cursor_pos
    if diff_data.new_window and vim.api.nvim_win_is_valid(diff_data.new_window) then
      cursor_pos = vim.api.nvim_win_get_cursor(diff_data.new_window)
    end

    -- Use the new follow_file_changes module for timing-based detection
    follow_file_changes.handle_file_change_with_timing_check(
      diff_data.old_file_path,
      diff_data.created_at,
      cursor_pos,
      diff_data.original_cursor_pos,
      function(was_modified)
        if was_modified then
          logger.debug("diff", "File was externally modified - treating as accepted")
          diff_data.status = "saved"
          cleanup_diff_state(tab_name, "diff tab closed after external file modification")
        else
          logger.debug("diff", "File not modified - treating as rejected")
          resolve_rejected(tab_name)
        end
      end
    )

    return true
  end

  return false
end

--- Manual buffer reload function for testing/debugging
-- @param file_path string Path to the file to reload
-- @param original_cursor_pos table Original cursor position
-- @return any Result from follow_file_changes.reload_file_buffers
function M.reload_file_buffers_manual(file_path, original_cursor_pos)
  local follow_file_changes = require("claudecode.follow_file_changes")
  return follow_file_changes.reload_file_buffers(file_path, original_cursor_pos)
end

return M