--- MCP-compliant blocking operations for claudecode.nvim diff
local M = {}

local logger = require("claudecode.logger")
local window_utils = require("claudecode.utils.window")

--- Set up blocking diff operation with simpler approach
-- @param params table Parameters for the diff
-- @param resolution_callback function Callback to call when diff resolves
-- @param register_diff_state function Function to register diff state
-- @param register_autocmds function Function to register autocmds
-- @param cleanup_diff_state function Function to clean up diff state
-- @param create_diff_view function Function to create diff view
-- @param active_diffs_table table The active diffs table
function M.setup_blocking_diff(
  params,
  resolution_callback,
  register_diff_state,
  register_autocmds,
  cleanup_diff_state,
  create_diff_view,
  active_diffs_table
)
  local tab_name = params.tab_name
  logger.debug("diff", "Setting up diff for:", params.old_file_path)

  -- Wrap the setup in error handling to ensure cleanup on failure
  local setup_success, setup_error = pcall(function()
    -- Step 1: Check if the file exists (allow new files)
    local old_file_exists = vim.fn.filereadable(params.old_file_path) == 1
    local is_new_file = not old_file_exists

    -- Step 2: Find if the file is already open in a buffer (only for existing files)
    local existing_buffer = nil
    local target_window = nil

    if old_file_exists then
      -- Look for existing buffer with this file
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
          local buf_name = vim.api.nvim_buf_get_name(buf)
          if buf_name == params.old_file_path then
            existing_buffer = buf
            break
          end
        end
      end

      -- Find window containing this buffer (if any)
      if existing_buffer then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == existing_buffer then
            target_window = win
            break
          end
        end
      end
    end

    -- If no existing buffer/window, find a suitable main editor window
    if not target_window then
      target_window = window_utils.find_main_editor_window()
    end

    -- Step 3: Create scratch buffer for new content
    local new_buffer = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
    if new_buffer == 0 then
      error({
        code = -32000,
        message = "Buffer creation failed",
        data = "Could not create new content buffer",
      })
    end

    local new_unique_name = is_new_file and (tab_name .. " (NEW FILE - proposed)") or (tab_name .. " (proposed)")
    vim.api.nvim_buf_set_name(new_buffer, new_unique_name)
    local lines = vim.split(params.new_file_contents, "\n")
    -- Remove trailing empty line if content ended with \n
    if #lines > 0 and lines[#lines] == "" then
      table.remove(lines, #lines)
    end
    vim.api.nvim_buf_set_lines(new_buffer, 0, -1, false, lines)

    vim.api.nvim_buf_set_option(new_buffer, "buftype", "acwrite") -- Allows saving but stays as scratch-like
    vim.api.nvim_buf_set_option(new_buffer, "modifiable", true)

    -- Step 4: Register initial diff state early to prevent race conditions
    register_diff_state(tab_name, {
      old_file_path = params.old_file_path,
      new_file_path = params.new_file_path,
      new_file_contents = params.new_file_contents,
      new_buffer = new_buffer,
      new_window = nil, -- Will be updated after diff view creation
      target_window = target_window,
      original_buffer = existing_buffer,
      original_cursor_pos = target_window and vim.api.nvim_win_get_cursor(target_window) or nil,
      original_window_view = target_window and vim.api.nvim_win_call(target_window, function()
        return vim.fn.winsaveview()
      end) or nil,
      autocmd_ids = {}, -- Will be updated after autocmd registration
      created_at = vim.fn.localtime(),
      status = "pending",
      resolution_callback = resolution_callback,
      result_content = nil,
      is_new_file = is_new_file,
      changed_lines = {}, -- Will be updated after diff view creation
    })
    
    -- Step 5: Set up diff view using the target window
    local diff_info = create_diff_view(
      target_window,
      params.old_file_path,
      new_buffer,
      tab_name,
      is_new_file,
      existing_buffer
    )

    -- Step 6: Register autocmds for user interaction monitoring
    -- Use the actual buffer the user interacts with (important for unified mode)
    local buffer_for_autocmds = diff_info.new_buffer or new_buffer
    local autocmd_ids = register_autocmds(tab_name, buffer_for_autocmds)

    -- Clean up original scratch buffer if unified mode created a different buffer
    if diff_info.new_buffer and diff_info.new_buffer ~= new_buffer then
      pcall(vim.api.nvim_buf_delete, new_buffer, { force = true })
    end

    -- Step 7: Update diff state with final values from diff view creation
    
    -- Get the current diff state and update it with the new information
    local current_diff_state = active_diffs_table[tab_name]
    if current_diff_state then
      -- Use cursor position and window view from diff view if available, otherwise keep the original
      local original_cursor_pos = diff_info.original_cursor_pos or current_diff_state.original_cursor_pos
      local original_window_view = diff_info.original_window_view or current_diff_state.original_window_view
      
      -- Update the diff state with new information from diff view creation
      current_diff_state.new_buffer = buffer_for_autocmds
      current_diff_state.new_window = diff_info.new_window
      current_diff_state.target_window = diff_info.target_window
      current_diff_state.original_buffer = diff_info.original_buffer or current_diff_state.original_buffer
      current_diff_state.original_cursor_pos = original_cursor_pos
      current_diff_state.original_window_view = original_window_view
      current_diff_state.autocmd_ids = autocmd_ids
      current_diff_state.changed_lines = diff_info.changed_lines or {}
    end
  end) -- End of pcall

  -- Handle setup errors
  if not setup_success then
    local error_msg = "Failed to setup diff operation: " .. tostring(setup_error)
    logger.error("diff", error_msg)

    -- Clean up any partial state that might have been created
    if active_diffs_table[tab_name] then
      cleanup_diff_state(tab_name, "setup failed")
    end

    -- Re-throw the error for MCP compliance
    error({
      code = -32000,
      message = "Diff setup failed",
      data = error_msg,
    })
  end
end

--- Blocking diff operation for MCP compliance
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @param active_diffs_table table The active diffs table
-- @param resolve_rejected function Function to resolve diff as rejected
-- @param setup_blocking_diff_func function Function to set up blocking diff
-- @return table MCP-compliant response with content array
function M.open_diff_blocking(
  old_file_path,
  new_file_path,
  new_file_contents,
  tab_name,
  active_diffs_table,
  resolve_rejected,
  setup_blocking_diff_func
)
  -- Check for existing diff with same tab_name
  if active_diffs_table[tab_name] then
    -- Resolve the existing diff as rejected before replacing
    resolve_rejected(tab_name)
  end

  -- Set up blocking diff operation
  local co = coroutine.running()
  if not co then
    error({
      code = -32000,
      message = "Internal server error",
      data = "openDiff must run in coroutine context",
    })
  end

  logger.debug("diff", "Starting diff setup for", tab_name)

  -- Use native diff implementation
  local success, err = pcall(setup_blocking_diff_func, {
    old_file_path = old_file_path,
    new_file_path = new_file_path,
    new_file_contents = new_file_contents,
    tab_name = tab_name,
  }, function(result)
    -- Resume the coroutine with the result
    local resume_success, resume_result = coroutine.resume(co, result)
    if resume_success then
      -- Use the global response sender to avoid module reloading issues
      local co_key = tostring(co)
      if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
        _G.claude_deferred_responses[co_key](resume_result)
        _G.claude_deferred_responses[co_key] = nil
      else
        logger.error("diff", "No global response sender found for coroutine:", co_key)
      end
    else
      logger.error("diff", "Coroutine failed:", tostring(resume_result))
      local co_key = tostring(co)
      if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
        _G.claude_deferred_responses[co_key]({
          error = {
            code = -32603,
            message = "Internal error",
            data = "Coroutine failed: " .. tostring(resume_result),
          },
        })
        _G.claude_deferred_responses[co_key] = nil
      end
    end
  end)

  if not success then
    logger.error("diff", "Diff setup failed for", tab_name, "error:", tostring(err))
    -- If the error is already structured, propagate it directly
    if type(err) == "table" and err.code then
      error(err)
    else
      error({
        code = -32000,
        message = "Error setting up diff",
        data = tostring(err),
      })
    end
  end

  -- Yield and wait indefinitely for user interaction - the resolve functions will resume us
  local user_action_result = coroutine.yield()
  logger.debug("diff", "User action completed for", tab_name)

  -- Return the result directly - this will be sent by the deferred response system
  return user_action_result
end

return M
