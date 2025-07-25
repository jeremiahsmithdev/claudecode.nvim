--- Unified diff parsing utilities for claudecode.nvim
local M = {}

local logger = require("claudecode.logger")

--- Parse unified diff output into hunks
-- @param diff_output string Raw git diff output
-- @return table Array of hunks
function M.parse_unified_diff(diff_output)
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
      logger.debug("parser", "Found hunk: old", old_start, old_count, "new", new_start, new_count)
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
            logger.debug("parser", "Found removed line:", line:sub(2))
          end
        end
      end
    end
  end

  logger.debug("parser", "Parsed", #hunks, "hunks from", line_count, "lines")
  for i, hunk in ipairs(hunks) do
    logger.debug(
      "parser",
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
function M.generate_unified_diff(old_file_path, new_content)
  local old_content = ""

  -- Read saved file content
  if vim.fn.filereadable(old_file_path) == 1 then
    local file = io.open(old_file_path, "r")
    if file then
      old_content = file:read("*all")
      file:close()
    end
  end

  logger.debug("parser", "generate_unified_diff for", old_file_path)
  logger.debug("parser", "old_content length:", #old_content, "ends with newline:", old_content:sub(-1) == "\n")
  logger.debug("parser", "new_content length:", #new_content, "ends with newline:", new_content:sub(-1) == "\n")

  -- Normalize newline endings to match original file
  local normalized_new_content = new_content
  if #old_content > 0 and #new_content > 0 then
    if old_content:sub(-1) == "\n" and new_content:sub(-1) ~= "\n" then
      normalized_new_content = new_content .. "\n"
      logger.debug("parser", "Added missing newline to match original file")
    elseif old_content:sub(-1) ~= "\n" and new_content:sub(-1) == "\n" then
      normalized_new_content = new_content:sub(1, -2)
      logger.debug("parser", "Removed extra newline to match original file")
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
  logger.debug("parser", "git diff exit code:", exit_code)

  -- Clean up temp files
  os.remove(old_tmp)
  os.remove(new_tmp)
  vim.fn.delete(tmp_dir, "d")

  logger.debug("parser", "git diff output length:", #result)
  if #result > 0 then
    logger.debug("parser", "git diff first 500 chars:", result:sub(1, 500))
  else
    logger.debug("parser", "git diff produced no output!")
  end

  -- Git diff returns exit code 1 when there are differences, which is normal
  if exit_code > 1 then
    logger.warn("parser", "git diff failed with exit code:", exit_code)
    return nil
  end

  return result
end

--- Count additions and deletions from parsed hunks
-- @param hunks table Array of hunks with lines
-- @return table {additions: number, deletions: number}
function M.count_diff_changes(hunks)
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

return M