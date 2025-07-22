--- Window utilities for claudecode.nvim
-- Shared window management functions used across the codebase.
local M = {}

--- Find a suitable main editor window.
-- Excludes terminals, sidebars, floating windows, and special buffer types.
-- @return number|nil Window ID of the main editor window, or nil if not found
function M.find_main_editor_window()
  local windows = vim.api.nvim_list_wins()

  for _, win in ipairs(windows) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
    local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    local win_config = vim.api.nvim_win_get_config(win)

    -- Check if this is a suitable window
    local is_suitable = true

    -- Skip floating windows
    if win_config.relative and win_config.relative ~= "" then
      is_suitable = false
    end

    -- Skip special buffer types
    if is_suitable and (buftype == "terminal" or buftype == "nofile" or buftype == "prompt") then
      is_suitable = false
    end

    -- Skip known sidebar filetypes and ClaudeCode terminal
    if
      is_suitable
      and (
        filetype == "neo-tree"
        or filetype == "neo-tree-popup"
        or filetype == "ClaudeCode"
        or filetype == "NvimTree"
        or filetype == "oil"
        or filetype == "aerial"
        or filetype == "tagbar"
      )
    then
      is_suitable = false
    end

    -- This looks like a main editor window
    if is_suitable then
      return win
    end
  end

  return nil
end

--- Get all valid editor windows.
-- Similar to find_main_editor_window but returns all suitable windows.
-- @return table Array of window IDs that are suitable for editing
function M.get_editor_windows()
  local windows = vim.api.nvim_list_wins()
  local editor_windows = {}

  for _, win in ipairs(windows) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
    local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    local win_config = vim.api.nvim_win_get_config(win)

    -- Check if this is a suitable window
    local is_suitable = true

    -- Skip floating windows
    if win_config.relative and win_config.relative ~= "" then
      is_suitable = false
    end

    -- Skip special buffer types
    if is_suitable and (buftype == "terminal" or buftype == "nofile" or buftype == "prompt") then
      is_suitable = false
    end

    -- Skip known sidebar filetypes and ClaudeCode terminal
    if
      is_suitable
      and (
        filetype == "neo-tree"
        or filetype == "neo-tree-popup"
        or filetype == "ClaudeCode"
        or filetype == "NvimTree"
        or filetype == "oil"
        or filetype == "aerial"
        or filetype == "tagbar"
      )
    then
      is_suitable = false
    end

    -- This looks like a suitable editor window
    if is_suitable then
      table.insert(editor_windows, win)
    end
  end

  return editor_windows
end

--- Check if a window is a suitable editor window.
-- @param win number Window ID to check
-- @return boolean true if the window is suitable for editing
function M.is_editor_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
  local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
  local win_config = vim.api.nvim_win_get_config(win)

  -- Skip floating windows
  if win_config.relative and win_config.relative ~= "" then
    return false
  end

  -- Skip special buffer types
  if buftype == "terminal" or buftype == "nofile" or buftype == "prompt" then
    return false
  end

  -- Skip known sidebar filetypes and ClaudeCode terminal
  if
    filetype == "neo-tree"
    or filetype == "neo-tree-popup"
    or filetype == "ClaudeCode"
    or filetype == "NvimTree"
    or filetype == "oil"
    or filetype == "aerial"
    or filetype == "tagbar"
  then
    return false
  end

  return true
end

return M
