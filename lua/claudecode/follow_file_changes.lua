--- Follow file changes module for Claude Code Neovim integration.
-- Handles automatic navigation to files after Claude edits them with instant response.
local M = {}

local logger = require("claudecode.logger")
local window_utils = require("claudecode.utils.window")

-- Global state for tracking diffs that have been externally saved
local externally_saved_files = {}

--- Force reload file buffers after external changes
-- @param file_path string Path to the file that was externally modified
-- @param original_cursor_pos table|nil Original cursor position to restore {row, col}
function M.reload_file_buffers(file_path, original_cursor_pos)
  logger.debug(
    "follow_file_changes",
    "Reloading buffers for file:",
    file_path,
    original_cursor_pos and "(restoring cursor)" or ""
  )

  local reloaded_count = 0
  -- Find and reload any open buffers for this file
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)

      -- Simple string match - if buffer name matches the file path
      if buf_name == file_path then
        -- Check if buffer is modified - only reload unmodified buffers for safety
        local modified = vim.api.nvim_buf_get_option(buf, "modified")
        logger.debug("follow_file_changes", "Found matching buffer", buf, "modified:", modified)

        if not modified then
          -- Try to find a window displaying this buffer for proper context
          local win_id = nil
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == buf then
              win_id = win
              break
            end
          end

          if win_id then
            vim.api.nvim_win_call(win_id, function()
              vim.cmd("edit!")
              -- Restore original cursor position if we have it
              if original_cursor_pos then
                pcall(vim.api.nvim_win_set_cursor, win_id, original_cursor_pos)
              end
            end)
          else
            vim.api.nvim_buf_call(buf, function()
              vim.cmd("edit!")
            end)
          end

          reloaded_count = reloaded_count + 1
        end
      end
    end
  end

  logger.debug(
    "follow_file_changes",
    "Completed buffer reload - reloaded",
    reloaded_count,
    "buffers for file:",
    file_path
  )
end

--- Calculate visual cursor position adjustment for fold-aware navigation
-- @param cursor_pos table Cursor position {row, col} from diff view
-- @param config table Configuration with diff_opts.lines_before_fold
-- @return table Adjusted cursor position and view positioning info
local function calculate_fold_aware_position(cursor_pos, config)
  if not cursor_pos or not config then
    return cursor_pos
  end

  local lines_before_fold = config.diff_opts and config.diff_opts.lines_before_fold or 4
  local row = cursor_pos[1]

  -- If cursor is positioned after folded content, we need to adjust the view
  -- The idea is: if in diff view cursor appears at visual line N due to folding,
  -- we want to position the actual file so target line appears at visual line N
  local visual_row_in_diff = math.min(row, lines_before_fold + 1)

  return {
    cursor_pos = cursor_pos,
    visual_position = visual_row_in_diff,
    lines_before_fold = lines_before_fold,
  }
end

--- Highlight the specific changed/added lines from diff data
--- @param bufnr number Buffer number
--- @param file_path string Path to the file
--- @param changed_lines table|nil Array of line numbers that were changed in the diff
local function highlight_changed_lines_from_diff(bufnr, file_path, changed_lines)
  logger.debug("follow_file_changes", "=== HIGHLIGHTING: Highlighting changed lines for", file_path, "===")

  if not bufnr or bufnr == -1 then
    logger.debug("follow_file_changes", "Invalid buffer, skipping highlighting")
    return
  end

  -- Use the changed lines passed as parameter
  changed_lines = changed_lines or {}
  logger.debug("follow_file_changes", "Using", #changed_lines, "changed lines for highlighting:", vim.inspect(changed_lines))

  if #changed_lines == 0 then
    logger.debug("follow_file_changes", "No changed lines found for highlighting")
    return
  end

  logger.debug("follow_file_changes", "Highlighting changed lines:", vim.inspect(changed_lines))

  -- Create namespace for our highlights
  local ns_id = vim.api.nvim_create_namespace("claude_code_changed_lines")
  -- Clear any existing highlights in this namespace
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Add visual-style highlighting to the changed lines
  for _, line_nr in ipairs(changed_lines) do
    if line_nr > 0 and line_nr <= vim.api.nvim_buf_line_count(bufnr) then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "Visual", line_nr - 1, 0, -1)
      logger.debug("follow_file_changes", "Highlighted line:", line_nr)
    end
  end

  logger.debug("follow_file_changes", "Applied highlights to", #changed_lines, "lines, will remove after 3 seconds")

  -- Remove highlights after 3 seconds
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      logger.debug("follow_file_changes", "Cleared change highlights from buffer", bufnr)
    end
  end, 3000)
end

--- Navigate to file after changes are applied (instant navigation)
-- @param file_path string Path to the file to navigate to
-- @param cursor_pos table|nil Cursor position to restore {row, col}
-- @param changed_lines table|nil Array of line numbers that were changed in the diff
function M.navigate_to_file_after_change(file_path, cursor_pos, changed_lines)
  logger.debug("follow_file_changes", "navigate_to_file_after_change called")
  logger.debug("follow_file_changes", "  file_path:", file_path)
  logger.debug("follow_file_changes", "  cursor_pos:", cursor_pos and vim.inspect(cursor_pos) or "nil")
  logger.debug("follow_file_changes", "  changed_lines:", changed_lines and #changed_lines or 0)

  -- Find a suitable main editor window (not terminal or sidebar)
  local target_win = window_utils.find_main_editor_window()
  logger.debug("follow_file_changes", "  target_win:", target_win)

  if target_win then
    -- Log current state before navigation
    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_win_get_buf(current_win)
    local current_file = vim.api.nvim_buf_get_name(current_buf)
    logger.debug(
      "follow_file_changes",
      "  Before navigation - win:",
      current_win,
      "buf:",
      current_buf,
      "file:",
      current_file
    )

    -- Switch to the target window
    vim.api.nvim_set_current_win(target_win)
    logger.debug("follow_file_changes", "  Switched to window:", target_win)

    -- Force reload the file to get latest content
    -- First, find if the file is already loaded in a buffer
    local file_bufnr = vim.fn.bufnr(file_path)
    if file_bufnr ~= -1 then
      -- Buffer exists, force reload from disk
      vim.api.nvim_buf_call(file_bufnr, function()
        vim.cmd("edit!")
      end)
      logger.debug("follow_file_changes", "  Force reloaded existing buffer:", file_bufnr)
    else
      -- Buffer doesn't exist, just open the file
      vim.cmd("edit " .. vim.fn.fnameescape(file_path))
      logger.debug("follow_file_changes", "  Opened new buffer for file")
    end

    -- Extra step: explicitly set the buffer in the window and trigger BufEnter
    local new_bufnr = vim.fn.bufnr(file_path)
    if new_bufnr ~= -1 then
      vim.api.nvim_win_set_buf(target_win, new_bufnr)

      -- Force check for external file changes
      vim.cmd("checktime")

      -- Trigger autocmds to ensure proper buffer setup
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = new_bufnr })
      vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = new_bufnr })

      logger.debug("follow_file_changes", "  Set buffer", new_bufnr, "in window", target_win, "and triggered autocmds")
    end

    -- Restore cursor position with fold-aware positioning (immediate, no delay)
    if cursor_pos then
      -- Get config for fold-aware positioning
      local main_module = require("claudecode")
      local config = main_module.state and main_module.state.config
      local fold_info = calculate_fold_aware_position(cursor_pos, config)

      -- Detect if winbar is present and adjust cursor position
      local winbar_offset = vim.api.nvim_win_get_option(target_win, "winbar") ~= "" and 1 or 0
      local adjusted_cursor_pos = { cursor_pos[1] + winbar_offset, cursor_pos[2] }

      logger.debug("follow_file_changes", "  Winbar offset:", winbar_offset, "original pos:", cursor_pos, "adjusted pos:", adjusted_cursor_pos)

      local success, err = pcall(vim.api.nvim_win_set_cursor, target_win, adjusted_cursor_pos)
      if success then
        logger.debug("follow_file_changes", "  Cursor set to:", adjusted_cursor_pos)

        -- Adjust view positioning to match diff view's visual positioning
        if fold_info and fold_info.visual_position then
          local current_line = adjusted_cursor_pos[1]
          local desired_visual_line = fold_info.visual_position

          -- Calculate where the top of the window should be to position
          -- the cursor line at the desired visual position, accounting for winbar
          local window_top_line = math.max(1, current_line - desired_visual_line + 1 - winbar_offset)

          -- Set the window's topline to achieve the desired visual positioning
          pcall(vim.api.nvim_win_call, target_win, function()
            vim.fn.winrestview({ topline = window_top_line, lnum = current_line, col = adjusted_cursor_pos[2] })
          end)

          logger.debug("follow_file_changes", "  Applied fold-aware positioning:")
          logger.debug("follow_file_changes", "    visual_position in diff:", desired_visual_line)
          logger.debug("follow_file_changes", "    window_top_line:", window_top_line)
          logger.debug("follow_file_changes", "    winbar_offset applied:", winbar_offset)
        end
      else
        logger.error("follow_file_changes", "  Failed to set cursor:", err)
      end

      -- Log final state
      local final_cursor = vim.api.nvim_win_get_cursor(target_win)
      logger.debug("follow_file_changes", "  Final cursor position:", final_cursor)
    else
      logger.debug("follow_file_changes", "  No cursor position to restore")
    end

    logger.debug("follow_file_changes", "Navigation completed for:", file_path)

    -- Highlight the changed lines from the diff for 3 seconds
    local final_bufnr = vim.fn.bufnr(file_path)
    if final_bufnr ~= -1 then
      highlight_changed_lines_from_diff(final_bufnr, file_path, changed_lines)
    end
  else
    logger.debug("follow_file_changes", "No suitable window found for navigation")
  end
end

--- Mark a file as externally saved (called by saveDocument tool)
-- @param file_path string Path to the file that was saved
function M.mark_file_as_externally_saved(file_path)
  logger.debug("follow_file_changes", "Marking file as externally saved:", file_path)
  externally_saved_files[file_path] = true
end

--- Check if a file was marked as externally saved and clear the flag
-- @param file_path string Path to the file to check
-- @return boolean true if the file was marked as externally saved
function M.check_and_clear_external_save_flag(file_path)
  local was_saved = externally_saved_files[file_path] or false
  externally_saved_files[file_path] = nil
  logger.debug("follow_file_changes", "Checked external save flag for", file_path, "result:", was_saved)
  return was_saved
end

--- Check if file was modified since given timestamp
-- @param file_path string Path to the file to check
-- @param created_at number Timestamp to compare against
-- @return boolean true if file was modified after the timestamp
function M.check_file_modification(file_path, created_at)
  local file_exists = vim.fn.filereadable(file_path) == 1
  if not file_exists then
    return false
  end

  local current_mtime = vim.fn.getftime(file_path)
  logger.debug("follow_file_changes", "File modification check:", file_path)
  logger.debug("follow_file_changes", "  current_mtime:", current_mtime, "vs created_at:", created_at)

  return current_mtime > created_at
end

--- Handle file change with instant navigation
-- @param file_path string Path to the file that changed
-- @param cursor_pos table|nil Cursor position to restore {row, col}
-- @param original_cursor_pos table|nil Fallback cursor position
-- @param changed_lines table|nil Array of line numbers that were changed in the diff
function M.handle_file_change(file_path, cursor_pos, original_cursor_pos, changed_lines)
  -- Check if follow_file_changes is enabled
  local main_module = require("claudecode")
  if not (main_module.state.config and main_module.state.config.follow_file_changes) then
    return
  end

  logger.debug("follow_file_changes", "Handling file change for:", file_path, "with", changed_lines and #changed_lines or 0, "changed lines")

  -- Use immediate navigation (no delay)
  M.reload_file_buffers(file_path, original_cursor_pos)
  M.navigate_to_file_after_change(file_path, cursor_pos or original_cursor_pos, changed_lines)
end

--- Handle file change with delayed re-check for timing-based detection
-- @param file_path string Path to the file to check
-- @param created_at number Timestamp when diff was created
-- @param cursor_pos table|nil Cursor position to restore
-- @param original_cursor_pos table|nil Fallback cursor position
-- @param callback function Callback to call when done (for cleanup)
-- @param changed_lines table|nil Array of line numbers that were changed in the diff
function M.handle_file_change_with_timing_check(file_path, created_at, cursor_pos, original_cursor_pos, callback, changed_lines)
  logger.debug("follow_file_changes", "Starting timing-based file change detection for:", file_path)

  -- First immediate check
  if M.check_file_modification(file_path, created_at) then
    logger.debug("follow_file_changes", "File was immediately modified - cleaning up before navigation")
    -- Call cleanup callback BEFORE navigation to prevent race conditions
    if callback then
      callback(true)
    end
    M.handle_file_change(file_path, cursor_pos, original_cursor_pos, changed_lines)
    return
  end

  -- File not modified yet - wait and re-check (Claude writes after close_tab)
  logger.debug("follow_file_changes", "File not modified yet - waiting 200ms and re-checking")
  vim.defer_fn(function()
    if M.check_file_modification(file_path, created_at) then
      logger.debug("follow_file_changes", "File was modified after delay - cleaning up before navigation")
      -- Call cleanup callback BEFORE navigation to prevent race conditions
      if callback then
        callback(true)
      end
      M.handle_file_change(file_path, cursor_pos, original_cursor_pos, changed_lines)
    else
      logger.debug("follow_file_changes", "File still not modified after delay")
      if callback then
        callback(false)
      end
    end
  end, 200) -- Reduced from 300ms to 200ms for faster response
end

return M
