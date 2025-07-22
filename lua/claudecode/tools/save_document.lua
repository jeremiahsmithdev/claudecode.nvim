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

  -- Trigger follow_file_changes navigation if enabled
  local main_module = require("claudecode")
  if main_module.state.config and main_module.state.config.follow_file_changes then
    -- Get current cursor position for preservation from the saved buffer
    local cursor_pos = nil
    local buffer_win = vim.fn.bufwinid(bufnr)
    if buffer_win > 0 then
      cursor_pos = vim.api.nvim_win_get_cursor(buffer_win)
    end
    
    local logger = require("claudecode.logger")
    logger.debug("save_document", "Triggering follow_file_changes for", params.filePath, "cursor:", cursor_pos)
    
    vim.schedule(function()
      local diff = require("claudecode.diff")
      -- Use expanded file path to ensure consistency
      local expanded_path = vim.fn.expand(params.filePath)
      diff._navigate_to_file_after_change(expanded_path, cursor_pos)
    end)
  end

  return { message = "File saved: " .. params.filePath }
end

return {
  name = "saveDocument",
  schema = nil, -- Internal tool
  handler = handler,
}
