--- Unified vs split mode logic for claudecode.nvim diff operations
local M = {}

local logger = require("claudecode.logger")
local utils = require("claudecode.utils")
local window_utils = require("claudecode.utils.window")

--- Count additions and deletions by comparing two buffers
-- @param original_buf number Original buffer
-- @param new_buf number New buffer
-- @return table {additions: number, deletions: number}
local function count_buffer_changes(original_buf, new_buf)
  local additions = 0
  local deletions = 0

  if not vim.api.nvim_buf_is_valid(original_buf) or not vim.api.nvim_buf_is_valid(new_buf) then
    return { additions = 0, deletions = 0 }
  end

  local original_lines = vim.api.nvim_buf_get_lines(original_buf, 0, -1, false)
  local new_lines = vim.api.nvim_buf_get_lines(new_buf, 0, -1, false)

  -- Simple line-by-line comparison for now
  -- This won't be as accurate as a proper diff algorithm, but gives a reasonable approximation
  local min_lines = math.min(#original_lines, #new_lines)

  -- Count changed lines in common section
  for i = 1, min_lines do
    if original_lines[i] ~= new_lines[i] then
      additions = additions + 1
      deletions = deletions + 1
    end
  end

  -- Count added/removed lines
  if #new_lines > #original_lines then
    additions = additions + (#new_lines - #original_lines)
  elseif #original_lines > #new_lines then
    deletions = deletions + (#original_lines - #new_lines)
  end

  return { additions = additions, deletions = deletions }
end

--- Format GitHub-style winbar content
-- @param changes table {additions: number, deletions: number}
-- @param filename string Name of the file being diffed
-- @return string Formatted winbar content
local function format_diff_winbar(changes, filename)
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

  -- Define Claude brand colors if not already defined
  vim.api.nvim_set_hl(0, "ClaudeOrange", { fg = "#FF6B35", bold = true })
  vim.api.nvim_set_hl(0, "ClaudeBrand", { fg = "#E5E7EB", bold = true })
  vim.api.nvim_set_hl(0, "ClaudeSubtle", { fg = "#6B7280" })
  vim.api.nvim_set_hl(0, "ClaudeWinbarBg", { bg = "#1F2937" }) -- Dark gray background

  local basename = vim.fn.fnamemodify(filename, ":t")
  -- Format with Claude branding and colors: ✻ Claude → filename | +N -N lines to be changed
  local content = string.format("%%#ClaudeOrange#✻%%#ClaudeWinbarBg# %%#ClaudeBrand#Claude%%#ClaudeWinbarBg# %%#ClaudeSubtle#→%%#ClaudeWinbarBg# %%#Directory#%s%%#ClaudeWinbarBg# %%#ClaudeSubtle#|%%#ClaudeWinbarBg# %s lines to be changed",
    basename, changes_text)
  return string.format("%%#ClaudeWinbarBg#%%=%s%%=%%*", content)
end

--- Set winbar for diff display
-- @param win number Window handle
-- @param changes table {additions: number, deletions: number}
-- @param filename string Name of the file being diffed
local function set_diff_winbar(win, changes, filename)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local winbar_content = format_diff_winbar(changes, filename)
  vim.api.nvim_set_option_value("winbar", winbar_content, { win = win })
end

--- Open native diff view (simple split mode implementation)
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table Result with provider, tab_name, and success status
function M.open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  -- Note: unified mode is handled in _create_diff_view_from_window
  local new_filename = vim.fn.fnamemodify(new_file_path, ":t") .. ".new"
  local tmp_file, err = utils.create_temp_file(new_file_contents, new_filename)
  if not tmp_file then
    return { provider = "native", tab_name = tab_name, success = false, error = err, temp_file = nil }
  end

  local target_win = window_utils.find_main_editor_window()

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd("wincmd t")
    vim.cmd("wincmd l")
    local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
    local buftype = vim.api.nvim_buf_get_option(buf, "buftype")

    if buftype == "terminal" or buftype == "nofile" then
      vim.cmd("vsplit")
    end
  end

  vim.cmd("edit " .. vim.fn.fnameescape(old_file_path))
  vim.cmd("diffthis")
  vim.cmd("vsplit")
  vim.cmd("edit " .. vim.fn.fnameescape(tmp_file))
  vim.api.nvim_buf_set_name(0, new_file_path .. " (New)")

  -- Propagate filetype to the proposed buffer for proper syntax highlighting (#20)
  local proposed_buf = vim.api.nvim_get_current_buf()
  local old_filetype = utils.detect_filetype(old_file_path)
  if old_filetype and old_filetype ~= "" then
    vim.api.nvim_set_option_value("filetype", old_filetype, { buf = proposed_buf })
  end

  vim.cmd("wincmd =")

  local new_buf = proposed_buf
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = new_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = new_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = new_buf })

  vim.cmd("diffthis")

  local cleanup_group = vim.api.nvim_create_augroup("ClaudeCodeDiffCleanup", { clear = false })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = cleanup_group,
    buffer = new_buf,
    callback = function()
      utils.cleanup_temp_file(tmp_file)
    end,
    once = true,
  })

  return {
    provider = "native",
    tab_name = tab_name,
    success = true,
    temp_file = tmp_file,
  }
end

--- Create diff view from a specific window (handles unified vs split mode)
-- @param target_window number The window to use as base for the diff
-- @param old_file_path string Path to the original file
-- @param new_buffer number New file buffer ID
-- @param tab_name string The diff identifier
-- @param is_new_file boolean Whether this is a new file (doesn't exist yet)
-- @param existing_buffer number|nil Existing buffer for the file (to avoid E37 error)
-- @return table Info about the created diff layout
function M.create_diff_view_from_window(
  target_window,
  old_file_path,
  new_buffer,
  tab_name,
  is_new_file,
  existing_buffer
)
  -- If no target window provided, create a new window in suitable location
  if not target_window then
    -- Try to create a new window in the main area
    vim.cmd("wincmd t") -- Go to top-left
    vim.cmd("wincmd l") -- Move right (to middle if layout is left|middle|right)

    local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
    local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
    local filetype = vim.api.nvim_buf_get_option(buf, "filetype")

    if buftype == "terminal" or buftype == "prompt" or filetype == "neo-tree" or filetype == "ClaudeCode" then
      vim.cmd("vsplit")
    end

    target_window = vim.api.nvim_get_current_win()
  else
    vim.api.nvim_set_current_win(target_window)
  end

  local original_buffer
  if is_new_file then
    local empty_buffer = vim.api.nvim_create_buf(false, true)
    if not empty_buffer or empty_buffer == 0 then
      local error_msg = "Failed to create empty buffer for new file diff"
      logger.error("diff", error_msg)
      error({
        code = -32000,
        message = "Buffer creation failed",
        data = error_msg,
      })
    end

    -- Set buffer properties with error handling
    local success, err = pcall(function()
      vim.api.nvim_buf_set_name(empty_buffer, old_file_path .. " (NEW FILE)")
      vim.api.nvim_buf_set_lines(empty_buffer, 0, -1, false, {})
      vim.api.nvim_buf_set_option(empty_buffer, "buftype", "nofile")
      vim.api.nvim_buf_set_option(empty_buffer, "modifiable", false)
      vim.api.nvim_buf_set_option(empty_buffer, "readonly", true)
    end)

    if not success then
      pcall(vim.api.nvim_buf_delete, empty_buffer, { force = true })
      local error_msg = "Failed to configure empty buffer: " .. tostring(err)
      logger.error("diff", error_msg)
      error({
        code = -32000,
        message = "Buffer configuration failed",
        data = error_msg,
      })
    end

    vim.api.nvim_win_set_buf(target_window, empty_buffer)
    original_buffer = empty_buffer
  else
    -- Use existing buffer if available to avoid E37 error with unsaved changes
    if existing_buffer and vim.api.nvim_buf_is_valid(existing_buffer) then
      vim.api.nvim_win_set_buf(target_window, existing_buffer)
      original_buffer = existing_buffer
    else
      vim.cmd("edit " .. vim.fn.fnameescape(old_file_path))
      original_buffer = vim.api.nvim_win_get_buf(target_window)
    end
  end

  -- Check if we're in unified mode
  local main_module = require("claudecode")
  local diff_mode = main_module.state.config.diff_opts.diff_mode or "split"

  local diff_info

  if diff_mode == "unified" then
    -- Unified mode: use dedicated unified_diff module
    local unified_diff = require("claudecode.unified_diff")

    -- Get new buffer content for unified diff
    local new_lines = vim.api.nvim_buf_get_lines(new_buffer, 0, -1, false)
    local new_content = table.concat(new_lines, "\n")

    -- Create unified diff view with config for folding
    local result = unified_diff.open_unified_diff(
      old_file_path,
      old_file_path, -- Use old_file_path for both since we want to show as editing the original
      new_content,
      tab_name,
      target_window,
      main_module.state.config, -- Pass config for lines_before_fold setting
      is_new_file -- Pass new file information for proper buffer naming
    )

    if result.success then
      diff_info = {
        new_window = target_window,
        target_window = target_window,
        original_buffer = original_buffer, -- Keep the actual original file buffer
        new_buffer = result.buffer, -- The unified diff buffer for cleanup tracking
        changed_lines = result.change_lines, -- Pass through changed lines for highlighting
      }
    else
      -- Fall back to split mode if unified diff fails
      logger.warn("unified_diff", "Failed to create unified diff, falling back to split mode")
      diff_mode = "split" -- Force split mode for fallback
    end
  end

  -- Only run split mode if we're not in unified mode or unified mode failed
  if diff_mode == "split" then
    -- Split mode: original behavior
    vim.cmd("diffthis")

    vim.cmd("vsplit")
    local new_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(new_win, new_buffer)

    -- Ensure new buffer inherits filetype from original for syntax highlighting (#20)
    local original_ft = utils.detect_filetype(old_file_path, original_buffer)
    if original_ft and original_ft ~= "" then
      vim.api.nvim_set_option_value("filetype", original_ft, { buf = new_buffer })
    end
    vim.cmd("diffthis")

    vim.cmd("wincmd =")
    vim.api.nvim_set_current_win(new_win)

    -- Set absolute line numbering for both diff windows
    if vim.api.nvim_win_is_valid(target_window) then
      vim.api.nvim_set_option_value("number", true, { win = target_window })
      vim.api.nvim_set_option_value("relativenumber", false, { win = target_window })
    end
    if vim.api.nvim_win_is_valid(new_win) then
      vim.api.nvim_set_option_value("number", true, { win = new_win })
      vim.api.nvim_set_option_value("relativenumber", false, { win = new_win })
    end

    -- Store diff context in buffer variables for user commands
    vim.b[new_buffer].claudecode_diff_tab_name = tab_name
    vim.b[new_buffer].claudecode_diff_new_win = new_win
    vim.b[new_buffer].claudecode_diff_target_win = target_window

    -- Set up GitHub-style winbar with diff statistics
    local changes = count_buffer_changes(original_buffer, new_buffer)
    set_diff_winbar(target_window, changes, old_file_path)
    set_diff_winbar(new_win, changes, old_file_path)
    logger.debug("modes", "Set split diff winbar with", changes.additions, "additions and", changes.deletions, "deletions")
    -- For split mode, create simple changed lines array based on buffer differences
    -- This is a simplified approach - for unified diff, the renderer provides exact line numbers
    local split_changed_lines = {}
    if changes.additions > 0 then
      -- Simple heuristic: assume changes are distributed through the file
      -- In a real implementation, this would come from actual diff analysis
      local new_lines = vim.api.nvim_buf_get_lines(new_buffer, 0, -1, false)
      for i = 1, #new_lines do
        if i <= changes.additions then
          table.insert(split_changed_lines, i)
        end
      end
    end

    -- Set diff_info for split mode
    diff_info = {
      new_window = new_win,
      target_window = target_window,
      original_buffer = original_buffer,
      new_buffer = new_buffer, -- For cleanup tracking
      changed_lines = split_changed_lines, -- Pass through changed lines for highlighting
    }
  end

  return diff_info
end

return M