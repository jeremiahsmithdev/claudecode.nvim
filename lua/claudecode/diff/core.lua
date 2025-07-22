--- Core diff operations and state management for claudecode.nvim
local M = {}

-- Global state management for active diffs
local active_diffs = {}
local autocmd_group

--- Get or create the autocmd group
local function get_autocmd_group()
  if not autocmd_group then
    autocmd_group = vim.api.nvim_create_augroup("ClaudeCodeMCPDiff", { clear = true })
  end
  return autocmd_group
end

--- Setup the diff module
-- @param user_diff_config table|nil Reserved for future use
function M.setup(user_diff_config)
  -- Currently no configuration needed for native diff
  -- Parameter kept for API compatibility
end

--- Register diff state for tracking
-- @param tab_name string Unique identifier for the diff
-- @param diff_data table Diff state data
function M.register_diff_state(tab_name, diff_data)
  active_diffs[tab_name] = diff_data
end

--- Get active diffs (for debugging and introspection)
-- @return table Copy of active diffs
function M.get_active_diffs()
  return vim.deepcopy(active_diffs)
end

--- Get autocmd group for diff operations
-- @return number Autocmd group ID
function M.get_autocmd_group()
  return get_autocmd_group()
end

--- Access to active diffs table for other diff modules
-- @return table Active diffs table (direct access for performance)
function M.get_active_diffs_table()
  return active_diffs
end

return M