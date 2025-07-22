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

  -- Mark any related diff as saved (for close_tab detection)
  local diff = require("claudecode.diff")
  local expanded_path = vim.fn.expand(params.filePath)
  diff._mark_diff_as_externally_saved(expanded_path)
  
  -- Trigger follow_file_changes navigation if enabled
  local main_module = require("claudecode")
  if main_module.state.config and main_module.state.config.follow_file_changes then
    local logger = require("claudecode.logger")
    local follow_file_changes = require("claudecode.follow_file_changes")
    
    -- Try to get cursor position from the current window (which might be the diff view)
    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_win_get_buf(current_win)
    local cursor_pos = vim.api.nvim_win_get_cursor(current_win)
    
    logger.debug("save_document", "Current window:", current_win, "buffer:", current_buf, "cursor:", cursor_pos)
    logger.debug("save_document", "Saved buffer:", bufnr, "file:", params.filePath)
    
    -- If we can't get a good cursor position, try from the saved buffer's window
    local buffer_win = vim.fn.bufwinid(bufnr)
    if buffer_win > 0 and buffer_win ~= current_win then
      cursor_pos = vim.api.nvim_win_get_cursor(buffer_win)
      logger.debug("save_document", "Using cursor from buffer window:", buffer_win, "cursor:", cursor_pos)
    end
    
    logger.debug("save_document", "Triggering follow_file_changes for", params.filePath, "final cursor:", cursor_pos)
    
    -- Use immediate navigation (no delay)
    follow_file_changes.navigate_to_file_after_change(expanded_path, cursor_pos)
  end

  return { message = "File saved: " .. params.filePath }
end

return {
  name = "saveDocument",
  schema = nil, -- Internal tool
  handler = handler,
}
