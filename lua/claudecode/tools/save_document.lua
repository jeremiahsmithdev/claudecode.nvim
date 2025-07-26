--- Tool implementation for saving a document.

--- Handles the saveDocument tool invocation.
-- Saves the specified file (buffer).
-- @param params table The input parameters for the tool.
-- @field params.filePath string Path to the file to save.
-- @return table A table with a message indicating success.
-- @error table A table with code, message, and data for JSON-RPC error if failed.
local function handler(params)
  if not params.filePath then
    error({ code = -32602, message = "Invalid params", data = "Missing filePath parameter" })
  end

  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    error({
      code = -32000,
      message = "File operation error",
      data = "File not open in editor: " .. params.filePath,
    })
  end

  local success, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("write")
  end)

  if not success then
    error({
      code = -32000,
      message = "File operation error",
      data = "Failed to save file " .. params.filePath .. ": " .. tostring(err),
    })
  end

  -- Check if this save is for an active diff and resolve it properly
  local diff = require("claudecode.diff")
  local expanded_path = vim.fn.expand(params.filePath)
  
  -- Find any active diff for this file
  local diff_resolved = false
  for tab_name, diff_data in pairs(diff._get_active_diffs()) do
    -- Check if this buffer is part of a pending diff
    if diff_data.status == "pending" and diff_data.new_buffer == bufnr then
      -- Properly resolve the diff (this handles closing, navigation, and auto-close)
      diff._resolve_diff_as_saved(tab_name, bufnr)
      diff_resolved = true
      break
    end
  end
  
  -- If no diff was resolved, still mark as externally saved for other tracking
  if not diff_resolved then
    diff._mark_diff_as_externally_saved(expanded_path)
  end

  -- Trigger follow_file_changes navigation if enabled and no diff was resolved
  -- (If a diff was resolved, navigation already happened in _resolve_diff_as_saved)
  if not diff_resolved then
    local main_module = require("claudecode")
    if main_module.state.config and main_module.state.config.follow_file_changes then
      local follow_file_changes = require("claudecode.follow_file_changes")

      -- Try to get cursor position from the current window (which might be the diff view)
      local current_win = vim.api.nvim_get_current_win()
      local cursor_pos = vim.api.nvim_win_get_cursor(current_win)

      -- If we can't get a good cursor position, try from the saved buffer's window
      local buffer_win = vim.fn.bufwinid(bufnr)
      if buffer_win > 0 and buffer_win ~= current_win then
        cursor_pos = vim.api.nvim_win_get_cursor(buffer_win)
      end

      -- Use immediate navigation (no delay)
      follow_file_changes.navigate_to_file_after_change(expanded_path, cursor_pos)
    end
  end

  return { message = "File saved: " .. params.filePath }
end

return {
  name = "saveDocument",
  schema = nil, -- Internal tool
  handler = handler,
}
