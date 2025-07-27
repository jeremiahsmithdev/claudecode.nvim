--- Unified diff implementation for claudecode.nvim
-- Backwards-compatible wrapper using modular diff components
local M = {}

local logger = require("claudecode.logger")
local parser = require("claudecode.diff.parser")
local renderer = require("claudecode.diff.renderer")

--- Open a unified diff view for a file
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (same as old for in-place edits)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @param target_window number Window to display the diff in
-- @param config table Configuration options including diff_opts.lines_before_fold
-- @param is_new_file boolean Whether this is a new file (doesn't exist yet)
-- @return table Result with success status and buffer info
function M.open_unified_diff(
  old_file_path,
  new_file_path,
  new_file_contents,
  tab_name,
  target_window,
  config,
  is_new_file
)
  logger.debug("unified_diff", "open_unified_diff called for", old_file_path)
  logger.debug(
    "unified_diff",
    "new_file_contents length:",
    #new_file_contents,
    "ends with newline:",
    new_file_contents:sub(-1) == "\n"
  )

  -- Determine buffer name first
  local buffer_name = is_new_file and (old_file_path .. " (NEW FILE)") or (old_file_path .. " (diff)")

  -- Check if buffer already exists and reuse it
  local existing_bufnr = vim.fn.bufnr(buffer_name)
  local buf
  if existing_bufnr ~= -1 and vim.api.nvim_buf_is_valid(existing_bufnr) then
    buf = existing_bufnr
    -- Set buffer to modifiable before clearing content
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    -- Clear buffer content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  else
    -- Create a new buffer
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, buffer_name)
  end

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "modifiable", true)

  -- For new files, just show the new content
  if is_new_file then
    local lines = vim.split(new_file_contents, "\n", { plain = true })
    if lines[#lines] == "" then
      table.remove(lines)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  else
    -- For existing files, show the new content (after applying the diff)
    local lines = vim.split(new_file_contents, "\n", { plain = true })
    if lines[#lines] == "" then
      table.remove(lines)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  -- Make buffer non-modifiable
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Set buffer in the target window
  vim.api.nvim_win_set_buf(target_window, buf)

  -- Set absolute line numbering for unified diff view
  vim.api.nvim_set_option_value("number", true, { win = target_window })
  vim.api.nvim_set_option_value("relativenumber", false, { win = target_window })

  -- Detect and set filetype
  local extension = old_file_path:match("%.([^%.]+)$")
  if extension then
    local ok, _ = pcall(vim.api.nvim_buf_set_option, buf, "filetype", extension)
    if not ok then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("filetype detect")
      end)
    end
  else
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("filetype detect")
    end)
  end

  -- Enable syntax highlighting
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("syntax enable")
  end)

  -- Generate diff and apply highlighting
  local diff_output = parser.generate_unified_diff(old_file_path, new_file_contents)
  local change_lines = {}
  local hunks = {}

  if diff_output and diff_output ~= "" then
    hunks = parser.parse_unified_diff(diff_output)
    change_lines = renderer.apply_unified_diff_highlighting(buf, hunks)
  end

  -- Set up GitHub-style winbar with Claude branding for unified diff
  local function set_unified_diff_winbar(win, diff_hunks, filename)
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    -- Define Claude brand colors
    vim.api.nvim_set_hl(0, "ClaudeOrange", { fg = "#FF6B35", bold = true })
    vim.api.nvim_set_hl(0, "ClaudeBrand", { fg = "#E5E7EB", bold = true })
    vim.api.nvim_set_hl(0, "ClaudeSubtle", { fg = "#6B7280" })
    vim.api.nvim_set_hl(0, "ClaudeWinbarBg", { bg = "#1F2937" })

    -- Count changes from hunks
    local changes = parser.count_diff_changes(diff_hunks)
    local parts = {}

    if changes.additions > 0 then
      table.insert(parts, string.format("%%#DiffAdd#+%d%%*", changes.additions))
    end

    if changes.deletions > 0 then
      table.insert(parts, string.format("%%#DiffDelete#-%d%%*", changes.deletions))
    end

    local changes_text
    if #parts == 0 then
      changes_text = "No changes"
    else
      changes_text = table.concat(parts, " ")
    end

    local basename = vim.fn.fnamemodify(filename, ":t")

    -- Format with Claude branding: ✻ Claude → filename | +N -N lines to be changed
    local content = string.format("%%#ClaudeOrange#✻%%#ClaudeWinbarBg# %%#ClaudeBrand#Claude%%#ClaudeWinbarBg# %%#ClaudeSubtle#→%%#ClaudeWinbarBg# %%#Directory#%s%%#ClaudeWinbarBg# %%#ClaudeSubtle#|%%#ClaudeWinbarBg# %s lines to be changed",
      basename, changes_text)
    local winbar_content = string.format("%%#ClaudeWinbarBg#%%=%s%%=%%*", content)

    vim.api.nvim_set_option_value("winbar", winbar_content, { win = win })
  end

  -- Apply winbar to unified diff
  set_unified_diff_winbar(target_window, hunks, old_file_path)

  -- Set up folding if configured and there are changes (including deletions)
  if config and config.diff_opts and #hunks > 0 then
    renderer.setup_unified_diff_folding(buf, change_lines, config)
    
    -- Navigate to first change for better user experience
    if #change_lines > 0 then
      vim.api.nvim_win_set_cursor(target_window, {change_lines[1], 0})
    end
  end

  -- Capture original cursor position and window view from target window for navigation
  local original_cursor_pos = nil
  local original_window_view = nil
  if target_window and vim.api.nvim_win_is_valid(target_window) then
    original_cursor_pos = vim.api.nvim_win_get_cursor(target_window)
    original_window_view = vim.api.nvim_win_call(target_window, function()
      return vim.fn.winsaveview()
    end)
    logger.debug("unified_diff", "Captured original cursor position:", vim.inspect(original_cursor_pos))
    logger.debug("unified_diff", "Captured original window view:", vim.inspect(original_window_view))
  end

  -- Store diff metadata
  vim.b[buf].claudecode_diff_data = {
    type = "unified",
    old_file_path = old_file_path,
    new_file_path = new_file_path,
    tab_name = tab_name,
    change_lines = change_lines,
    is_new_file = is_new_file,
    hunks = hunks,
    original_cursor_pos = original_cursor_pos,
    original_window_view = original_window_view,
  }

  -- Return result
  local result = {
    success = true,
    bufnr = buf,
    type = "unified",
    new_buf = buf,
    new_buffer = buf, -- For compatibility with blocking mechanism
    new_window = target_window, -- For compatibility with blocking mechanism
    change_lines = change_lines,
    original_cursor_pos = original_cursor_pos,
    original_window_view = original_window_view,
    stats = parser.count_diff_changes(hunks),
  }

  logger.debug("unified_diff", "Unified diff opened successfully for", old_file_path)
  return result
end

--- Clean up unified diff resources
-- @param buf number Buffer handle
function M.cleanup_unified_diff(buf)
  renderer.cleanup_unified_diff(buf)
end

return M