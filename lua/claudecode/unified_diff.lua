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
  local line_count = 0

  for line in diff_output:gmatch("[^\n]*") do
    line_count = line_count + 1
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
      logger.debug("unified_diff", "Found hunk: old", old_start, old_count, "new", new_start, new_count)
    elseif current_hunk then
      -- Skip "No newline at end of file" markers
      if not line:match("^\\ No newline at end of file") then
        -- Parse diff line content
        local prefix = line:sub(1, 1)
        if prefix == "+" or prefix == "-" or prefix == " " then
          local line_type = prefix == "+" and "add" or (prefix == "-" and "remove" or "context")
          table.insert(current_hunk.lines, {
            type = line_type,
            content = line:sub(2), -- Remove the +/- prefix
          })
          if line_type == "remove" then
            logger.debug("unified_diff", "Found removed line:", line:sub(2))
          end
        end
      end
    end
  end

  logger.debug("unified_diff", "Parsed", #hunks, "hunks from", line_count, "lines")
  for i, hunk in ipairs(hunks) do
    logger.debug(
      "unified_diff",
      "Hunk",
      i,
      ":",
      "old_start =",
      hunk.old_start,
      "new_start =",
      hunk.new_start,
      "lines =",
      #hunk.lines
    )
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

  logger.debug("unified_diff", "generate_unified_diff for", old_file_path)
  logger.debug("unified_diff", "old_content length:", #old_content, "ends with newline:", old_content:sub(-1) == "\n")
  logger.debug("unified_diff", "new_content length:", #new_content, "ends with newline:", new_content:sub(-1) == "\n")

  -- Normalize newline endings to match original file
  local normalized_new_content = new_content
  if #old_content > 0 and #new_content > 0 then
    if old_content:sub(-1) == "\n" and new_content:sub(-1) ~= "\n" then
      normalized_new_content = new_content .. "\n"
      logger.debug("unified_diff", "Added missing newline to match original file")
    elseif old_content:sub(-1) ~= "\n" and new_content:sub(-1) == "\n" then
      normalized_new_content = new_content:sub(1, -2)
      logger.debug("unified_diff", "Removed extra newline to match original file")
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
    new_file:write(normalized_new_content)
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

  local exit_code = vim.v.shell_error
  logger.debug("unified_diff", "git diff exit code:", exit_code)

  -- Clean up temp files
  os.remove(old_tmp)
  os.remove(new_tmp)
  vim.fn.delete(tmp_dir, "d")

  logger.debug("unified_diff", "git diff output length:", #result)
  if #result > 0 then
    logger.debug("unified_diff", "git diff first 500 chars:", result:sub(1, 500))
  else
    logger.debug("unified_diff", "git diff produced no output!")
  end

  -- Git diff returns exit code 1 when there are differences, which is normal
  if exit_code > 1 then
    logger.warn("unified_diff", "git diff failed with exit code:", exit_code)
    return nil
  end

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
  local has_deletion_at_start = false
  local deleted_lines_at_start = 0

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
        -- For removed lines at the beginning, attach to line 0 with virt_lines_above = true
        local attach_line = 0
        if new_line_idx > 0 then
          -- For removals not at the beginning, attach to the previous line
          attach_line = math.min(new_line_idx - 1, buf_line_count - 1)
          attach_line = math.max(attach_line, 0)
        else
          -- Track deletions at the very beginning
          has_deletion_at_start = true
          deleted_lines_at_start = deleted_lines_at_start + 1
        end

        logger.debug(
          "unified_diff",
          "Applying removed line virtual text at line",
          attach_line,
          "new_line_idx:",
          new_line_idx,
          "content:",
          line.content,
          "buf_line_count:",
          buf_line_count
        )

        -- Always show above the attachment line
        vim.api.nvim_buf_set_extmark(buf, ns_id, attach_line, 0, {
          virt_lines = { { { line.content, "DiffDelete" } } },
          virt_lines_above = true,
          -- Removed sign_text as it appears on wrong line with virtual text
        })
        table.insert(change_lines, attach_line + 1) -- 1-indexed for navigation

        -- Don't increment new_line_idx for removed lines
      elseif line.type == "context" then
        -- Context line - just move forward
        new_line_idx = new_line_idx + 1
      end
    end
  end

  -- Apply topfill workaround if we have deletions at the beginning
  if has_deletion_at_start then
    -- Create an autocmd group for this buffer
    local augroup = vim.api.nvim_create_augroup("ClaudeCodeUnifiedDiffTopfill_" .. buf, { clear = true })

    -- Set topfill for virtual text above first line
    local topfill = deleted_lines_at_start

    -- Apply topfill in the next tick to ensure window is ready
    vim.schedule(function()
      local win = vim.fn.bufwinid(buf)
      if win > 0 then
        vim.fn.win_execute(win, "lua vim.fn.winrestview({ topfill = " .. topfill .. " })")

        -- Set up autocmd to maintain topfill on cursor movement
        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
          group = augroup,
          buffer = buf,
          callback = function()
            local current_win = vim.fn.bufwinid(buf)
            if current_win > 0 then
              vim.fn.win_execute(current_win, "lua vim.fn.winrestview({ topfill = " .. topfill .. " })")
            end
          end,
        })
      end
    end)
  end

  return change_lines
end

--- Set up basic folding for unchanged sections (simplified version of split diff)
-- @param buf number Buffer handle
-- @param change_lines table Array of line numbers with changes
-- @param config table Configuration options including lines_before_fold
local function setup_unified_diff_folding(buf, change_lines, config)
  if #change_lines == 0 then
    return
  end

  -- Enable folding (both options are window-local, set in current window)
  vim.api.nvim_set_option_value("foldenable", true, { win = 0 })
  vim.api.nvim_set_option_value("foldmethod", "manual", { win = 0 })

  local buf_line_count = vim.api.nvim_buf_line_count(buf)
  local context = config and config.diff_opts and config.diff_opts.lines_before_fold or 4 -- Configurable lines of context around changes

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

--- Count additions and deletions from parsed hunks
-- @param hunks table Array of hunks with lines
-- @return table {additions: number, deletions: number}
local function count_diff_changes(hunks)
  local additions = 0
  local deletions = 0

  for _, hunk in ipairs(hunks) do
    for _, line in ipairs(hunk.lines) do
      if line.type == "add" then
        additions = additions + 1
      elseif line.type == "remove" then
        deletions = deletions + 1
      end
    end
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

  -- Format: Claude Code - filename | +N -N lines to be changed (centered)
  local basename = vim.fn.fnamemodify(filename, ":t")
  local content = string.format("Claude Code - %s | %s lines to be changed", basename, changes_text)
  return string.format("%%=%s%%=", content)
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
    logger.debug("unified_diff", "Reusing existing buffer:", buffer_name)
    buf = existing_bufnr
    -- Ensure buffer is modifiable when reusing
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  else
    logger.debug("unified_diff", "Creating new buffer:", buffer_name)
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, buffer_name)
  end

  -- Populate buffer with NEW file content (so it's fully editable)
  local new_lines = vim.split(new_file_contents, "\n")
  logger.debug("unified_diff", "vim.split produced", #new_lines, "lines")
  if #new_lines > 0 then
    logger.debug("unified_diff", "Last line is empty:", new_lines[#new_lines] == "")
  end

  -- vim.split adds empty string at end if content ends with \n
  -- Remove it to match how Neovim handles file content
  if #new_lines > 0 and new_lines[#new_lines] == "" then
    logger.debug("unified_diff", "Removing empty last line")
    table.remove(new_lines, #new_lines)
  end

  -- Ensure buffer is modifiable before setting content
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)

  -- Detect and set original filetype for syntax highlighting
  local ft = vim.filetype and vim.filetype.match({ filename = old_file_path }) or ""
  if ft ~= "" then
    vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
  end

  -- Set buffer properties (use acwrite to allow :w like split mode)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

  -- Set absolute line numbering for diff buffer
  if target_window and vim.api.nvim_win_is_valid(target_window) then
    vim.api.nvim_set_option_value("number", true, { win = target_window })
    vim.api.nvim_set_option_value("relativenumber", false, { win = target_window })
  end

  -- Generate diff and apply highlighting
  local diff_output = generate_unified_diff(old_file_path, new_file_contents)
  local change_lines = {}
  local hunks = {}

  if diff_output and diff_output ~= "" then
    hunks = parse_unified_diff(diff_output)
    change_lines = apply_unified_diff_highlighting(buf, hunks)
  end

  -- Show the buffer in target window
  if target_window and vim.api.nvim_win_is_valid(target_window) then
    vim.api.nvim_win_set_buf(target_window, buf)
    vim.api.nvim_set_current_win(target_window)

    -- Set up folding and navigation (split diff features) after buffer is in window
    if change_lines then
      setup_unified_diff_folding(buf, change_lines, config)
    end
  end

  -- Navigate to first change
  navigate_to_first_change(buf, change_lines)

  -- Set up GitHub-style winbar with diff statistics
  if target_window and vim.api.nvim_win_is_valid(target_window) then
    local changes = count_diff_changes(hunks)
    set_diff_winbar(target_window, changes, old_file_path)
    logger.debug("unified_diff", "Set winbar with", changes.additions, "additions and", changes.deletions, "deletions")
  end

  -- Store diff context for cleanup and user commands
  vim.b[buf].claudecode_diff_tab_name = tab_name
  vim.b[buf].claudecode_diff_new_win = target_window -- For unified mode, new_win is the same as target_window
  vim.b[buf].claudecode_diff_target_win = target_window

  logger.debug("unified_diff", "Created unified diff for", old_file_path, "with", #change_lines, "changes")
  logger.debug("unified_diff", "Parsed", #hunks, "hunks from diff output")

  return {
    success = true,
    buffer = buf,
    change_lines = change_lines,
    provider = "unified",
  }
end

-- This function cleans up extmarks when unified diff is closed
-- Testing newline normalization fix - should eliminate last line issue

--- Clean up unified diff resources
-- @param buf number Buffer handle
function M.cleanup_unified_diff(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    -- Clean up topfill autocmd group
    pcall(vim.api.nvim_del_augroup_by_name, "ClaudeCodeUnifiedDiffTopfill_" .. buf)
  end
end

return M
-- Test line added for diff functionality verification
