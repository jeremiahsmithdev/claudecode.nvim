--- Unified diff implementation for claudecode.nvim
-- Combines vgit.nvim/unified.nvim approach with split diff navigation/folding features
local M = {}

local logger = require("claudecode.logger")

-- Namespace for diff highlighting
local ns_id = vim.api.nvim_create_namespace("claudecode_unified_diff")

--- Parse unified diff output into hunks (from unified.nvim approach)
-- @param diff_output string Raw git diff output
-- @return table Array of hunks
local function parse_unified_diff(diff_output)
  local hunks = {}
  local current_hunk = nil

  for line in diff_output:gmatch("[^\n]*") do
    -- Parse hunk header: @@ -old_start,old_count +new_start,new_count @@
    local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
    if old_start then
      current_hunk = {
        old_start = tonumber(old_start),
        old_count = tonumber(old_count) or 1,
        new_start = tonumber(new_start),
        new_count = tonumber(new_count) or 1,
        lines = {},
      }
      table.insert(hunks, current_hunk)
    elseif current_hunk then
      -- Parse diff line content
      local prefix = line:sub(1, 1)
      if prefix == "+" or prefix == "-" or prefix == " " then
        table.insert(current_hunk.lines, {
          type = prefix == "+" and "add" or (prefix == "-" and "remove" or "context"),
          content = line:sub(2), -- Remove the +/- prefix
        })
      end
    end
  end

  return hunks
end

--- Generate unified diff between saved file and new content
-- @param old_file_path string Path to the original file
-- @param new_content string New file contents
-- @return string|nil Unified diff output or nil on error
local function generate_unified_diff(old_file_path, new_content)
  local old_content = ""

  -- Read saved file content
  if vim.fn.filereadable(old_file_path) == 1 then
    local file = io.open(old_file_path, "r")
    if file then
      old_content = file:read("*all")
      file:close()
    end
  end

  -- Create temporary files for diff
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  local old_tmp = tmp_dir .. "/old"
  local new_tmp = tmp_dir .. "/new"

  local old_file = io.open(old_tmp, "w")
  if old_file then
    old_file:write(old_content)
    old_file:close()
  else
    return nil
  end

  local new_file = io.open(new_tmp, "w")
  if new_file then
    new_file:write(new_content)
    new_file:close()
  else
    return nil
  end

  -- Generate unified diff
  local result = vim.fn.system({
    "git",
    "diff",
    "--no-index",
    "--no-prefix",
    "--unified=3",
    old_tmp,
    new_tmp,
  })

  -- Clean up temp files
  os.remove(old_tmp)
  os.remove(new_tmp)
  vim.fn.delete(tmp_dir, "d")

  return result
end

--- Apply unified diff highlighting (based on vgit.nvim/unified.nvim approach)
-- @param buf number Buffer handle
-- @param hunks table Array of diff hunks
-- @return table Array of change line numbers for navigation
local function apply_unified_diff_highlighting(buf, hunks)
  -- Clear existing highlighting
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local change_lines = {}
  local buf_line_count = vim.api.nvim_buf_line_count(buf)

  for _, hunk in ipairs(hunks) do
    local new_line_idx = hunk.new_start - 1 -- 0-indexed

    for _, line in ipairs(hunk.lines) do
      if line.type == "add" then
        -- Highlight added line with + sign (vgit.nvim style)
        if new_line_idx < buf_line_count then
          vim.api.nvim_buf_set_extmark(buf, ns_id, new_line_idx, 0, {
            sign_text = "+",
            sign_hl_group = "DiffAdd",
            line_hl_group = "DiffAdd",
          })
          table.insert(change_lines, new_line_idx + 1) -- 1-indexed for navigation
        end
        new_line_idx = new_line_idx + 1
      elseif line.type == "remove" then
        -- Show removed line as virtual text (unified.nvim style)
        local attach_line = math.max(new_line_idx - 1, 0)
        if attach_line < buf_line_count then
          vim.api.nvim_buf_set_extmark(buf, ns_id, attach_line, 0, {
            virt_lines = { { { line.content, "DiffDelete" } } },
            virt_lines_above = true,
            sign_text = "-",
            sign_hl_group = "DiffDelete",
          })
          table.insert(change_lines, attach_line + 1) -- 1-indexed for navigation
        end
        -- Don't increment new_line_idx for removed lines
      elseif line.type == "context" then
        -- Context line - just move forward
        new_line_idx = new_line_idx + 1
      end
    end
  end

  return change_lines
end

--- Set up basic folding for unchanged sections (simplified version of split diff)
-- @param buf number Buffer handle
-- @param change_lines table Array of line numbers with changes
local function setup_unified_diff_folding(buf, change_lines)
  if #change_lines == 0 then
    return
  end

  -- Enable folding (both options are window-local, set in current window)
  vim.api.nvim_set_option_value("foldenable", true, { win = 0 })
  vim.api.nvim_set_option_value("foldmethod", "manual", { win = 0 })

  local buf_line_count = vim.api.nvim_buf_line_count(buf)
  local context = 3 -- Lines of context around changes

  -- Create folds for sections without changes
  local last_change_end = 1

  for _, change_line in ipairs(change_lines) do
    local fold_start = last_change_end
    local fold_end = math.max(1, change_line - context - 1)

    -- Create fold if there's enough unchanged content
    if fold_end > fold_start + 10 then -- Only fold if > 10 lines
      vim.api.nvim_buf_call(buf, function()
        vim.cmd(string.format("%d,%dfold", fold_start, fold_end))
      end)
    end

    last_change_end = math.min(buf_line_count, change_line + context + 1)
  end

  -- Fold remaining content at end if significant
  if last_change_end < buf_line_count - 10 then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd(string.format("%d,%dfold", last_change_end, buf_line_count))
    end)
  end
end

--- Navigate to first change (like split diff does)
-- @param buf number Buffer handle
-- @param change_lines table Array of change line numbers
local function navigate_to_first_change(buf, change_lines)
  if #change_lines > 0 then
    -- Navigate to first change
    local first_change = change_lines[1]
    vim.api.nvim_buf_call(buf, function()
      vim.api.nvim_win_set_cursor(0, { first_change, 0 })
    end)
  end
end

--- Open unified diff view combining vgit/unified highlighting with split diff features
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @param target_window number Window to display the diff in
-- @return table Result with success status and buffer info
function M.open_unified_diff(old_file_path, new_file_path, new_file_contents, tab_name, target_window)
  -- Create buffer with NEW file content (so it's fully editable)
  local buf = vim.api.nvim_create_buf(false, true)
  local new_lines = vim.split(new_file_contents, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  vim.api.nvim_buf_set_name(buf, old_file_path .. " (diff)")

  -- Detect and set original filetype for syntax highlighting
  local ft = vim.filetype and vim.filetype.match({ filename = old_file_path }) or ""
  if ft ~= "" then
    vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
  end

  -- Set buffer properties
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

  -- Generate diff and apply highlighting
  local diff_output = generate_unified_diff(old_file_path, new_file_contents)
  local change_lines = {}

  if diff_output and diff_output ~= "" then
    local hunks = parse_unified_diff(diff_output)
    change_lines = apply_unified_diff_highlighting(buf, hunks)
  end

  -- Show the buffer in target window
  if target_window and vim.api.nvim_win_is_valid(target_window) then
    vim.api.nvim_win_set_buf(target_window, buf)
    vim.api.nvim_set_current_win(target_window)

    -- Set up folding and navigation (split diff features) after buffer is in window
    if change_lines then
      setup_unified_diff_folding(buf, change_lines)
    end
  end

  -- Navigate to first change
  navigate_to_first_change(buf, change_lines)

  -- Store diff context for cleanup
  vim.b[buf].claudecode_diff_tab_name = tab_name
  vim.b[buf].claudecode_diff_target_win = target_window

  logger.debug("unified_diff", "Created unified diff for", old_file_path, "with", #change_lines, "changes")

  return {
    success = true,
    buffer = buf,
    change_lines = change_lines,
    provider = "unified",
  }
end

--- Clean up unified diff resources
-- @param buf number Buffer handle
function M.cleanup_unified_diff(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  end
end

return M
-- Test line added for diff functionality verification
