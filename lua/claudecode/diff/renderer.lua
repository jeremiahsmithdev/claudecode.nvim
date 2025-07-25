--- Unified diff rendering and highlighting for claudecode.nvim
local M = {}

local logger = require("claudecode.logger")

-- Namespace for diff highlighting
local ns_id = vim.api.nvim_create_namespace("claudecode_unified_diff")

--- Apply unified diff highlighting
-- @param buf number Buffer handle
-- @param hunks table Array of diff hunks
-- @return table Array of change line numbers for navigation
function M.apply_unified_diff_highlighting(buf, hunks)
  -- Clear existing highlighting
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local change_lines = {}
  local buf_line_count = vim.api.nvim_buf_line_count(buf)
  local has_deletion_at_start = false
  local deleted_lines_at_start = 0

  for _, hunk in ipairs(hunks) do
    -- Track both old and new line positions separately
    local old_line_idx = hunk.old_start - 1 -- 0-indexed, for tracking deletions
    local new_line_idx = hunk.new_start - 1 -- 0-indexed, for tracking additions

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

          logger.debug(
            "renderer",
            "Applied addition highlight at buffer line",
            new_line_idx,
            "content:",
            vim.api.nvim_buf_get_lines(buf, new_line_idx, new_line_idx + 1, false)[1] or ""
          )
        end
        new_line_idx = new_line_idx + 1
      elseif line.type == "remove" then
        -- Show removed line as virtual text above the current new line position
        -- This shows deletions at the position where they occurred in the old file
        local attach_line

        if new_line_idx == 0 then
          -- Deletions at the very beginning
          attach_line = 0
          has_deletion_at_start = true
          deleted_lines_at_start = deleted_lines_at_start + 1
        else
          -- Attach deletions to the line where they would appear in the new content
          -- Use new_line_idx directly (not new_line_idx - 1) so deletions appear
          -- above the line that replaced them or the next context line
          attach_line = math.min(new_line_idx, buf_line_count - 1)
        end

        logger.debug(
          "renderer",
          "Applying removed line virtual text at buffer line",
          attach_line,
          "old_line:",
          old_line_idx + 1,
          "new_line:",
          new_line_idx,
          "content:",
          line.content
        )

        -- Show deleted content as virtual text above in red
        vim.api.nvim_buf_set_extmark(buf, ns_id, attach_line, 0, {
          virt_lines = { { { line.content, "DiffDelete" } } },
          virt_lines_above = true,
        })

        -- Only increment old line index for removed lines
        old_line_idx = old_line_idx + 1
      elseif line.type == "context" then
        -- Context line - increment both counters
        old_line_idx = old_line_idx + 1
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

--- Set up basic folding for unchanged sections
-- @param buf number Buffer handle
-- @param change_lines table Array of line numbers with changes
-- @param config table Configuration options including lines_before_fold
function M.setup_unified_diff_folding(buf, change_lines, config)
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