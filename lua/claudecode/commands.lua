--- User command definitions for Claude Code Neovim integration.
-- Contains all user-facing commands and their implementations.
local M = {}

local logger = require("claudecode.logger")

--- Set up all user commands
function M.setup()
  local state = require("claudecode.state")
  local terminal = require("claudecode.terminal")

  -- Core control commands
  vim.api.nvim_create_user_command("ClaudeCodeStart", function()
    local init = require("claudecode.init")
    init.start()
  end, {
    desc = "Start Claude Code integration",
  })

  vim.api.nvim_create_user_command("ClaudeCodeStop", function()
    local init = require("claudecode.init")
    init.stop()
  end, {
    desc = "Stop Claude Code integration",
  })

  vim.api.nvim_create_user_command("ClaudeCreateLockfile", function()
    local init = require("claudecode.init")
    local success, result = init.start(false) -- Don't show startup notification
    if success then
      logger.info("command", "Claude Code lockfile created on port " .. tostring(result))
    else
      logger.error("command", "Failed to create lockfile: " .. tostring(result))
    end
  end, {
    desc = "Create Claude Code lockfile (start server without notification)",
  })

  vim.api.nvim_create_user_command("ClaudeCodeStatus", function()
    local main_module = require("claudecode")
    if main_module.state.server and main_module.state.port then
      logger.info("command", "Claude Code integration is running on port " .. tostring(main_module.state.port))
      
      -- Also show connection status like main does
      if main_module.is_claude_connected and main_module.is_claude_connected() then
        logger.info("command", "Claude Code is connected")
      else
        logger.info("command", "Claude Code is not connected (no active clients)")
      end
    else
      logger.info("command", "Claude Code integration is not running")
    end
  end, {
    desc = "Show Claude Code integration status",
  })

  -- Send commands (selection and file handling)
  local function get_visual_selection()
    local current_mode = vim.fn.mode()
    if current_mode == "v" or current_mode == "V" or current_mode == "\22" then
      -- Use cursor + anchor approach from main branch (more reliable)
      local cursor_pos = vim.api.nvim_win_get_cursor(0)[1]
      local anchor_pos = vim.fn.getpos("v")[2]
      
      local start_line, end_line
      if anchor_pos > 0 then
        start_line = math.min(cursor_pos, anchor_pos)
        end_line = math.max(cursor_pos, anchor_pos)
      else
        -- Fallback: just use current cursor position
        start_line = cursor_pos
        end_line = cursor_pos
      end
      
      return {
        start_line = start_line,
        end_line = end_line,
        start_col = 1,  -- Simplified for now
        end_col = 1,    -- Simplified for now
      }
    else
      -- Not in visual mode, try to use the marks (they should be valid now)
      local mark_start = vim.fn.getpos("'<")[2]
      local mark_end = vim.fn.getpos("'>")[2]
      
      if mark_start > 0 and mark_end > 0 then
        return {
          start_line = mark_start,
          end_line = mark_end,
          start_col = 1,
          end_col = 1,
        }
      end
    end
    return nil
  end

  local function send_selection(file_path, start_line, end_line)
    local init = require("claudecode.init")
    local success, error_msg = init.send_at_mention(file_path, start_line - 1, end_line - 1, "visual selection")
    if not success then
      logger.error("command", "Failed to send selection: " .. (error_msg or "unknown error"))
    else
      -- Auto-navigate to tmux pane after successful send
      logger.info("command", "ClaudeCodeSend successful, checking tmux navigation")
      local terminal_module = require("claudecode.terminal")
      local is_tmux = terminal_module.is_tmux_provider()
      logger.info("command", "is_tmux_provider():", is_tmux)
      
      if is_tmux then
        logger.info("command", "Tmux mode detected, attempting navigation")
        -- Get the tmux provider to check for active pane
        local tmux_provider = require("claudecode.terminal.tmux")
        if tmux_provider and tmux_provider.get_active_pane_id then
          local pane_id = tmux_provider.get_active_pane_id()
          logger.info("command", "Found tmux pane_id:", pane_id)
          if pane_id then
            -- Automatically switch to tmux pane
            local cmd = "tmux select-pane -t " .. pane_id
            logger.info("command", "Executing tmux navigation command:", cmd)
            local result = vim.fn.system(cmd)
            logger.info("command", "Tmux navigation result:", result)
            logger.info("command", "Auto-navigated to tmux pane:", pane_id)
          else
            logger.warn("command", "No tmux pane_id found for navigation")
          end
        else
          logger.warn("command", "Tmux provider or get_active_pane_id function not available")
        end
      else
        logger.info("command", "Not in tmux mode, skipping navigation")
      end
    end
  end

  local function unified_send_handler(opts)
    local selection = get_visual_selection()
    if selection then
      local file_path = vim.api.nvim_buf_get_name(0)
      if file_path and file_path ~= "" then
        send_selection(file_path, selection.start_line, selection.end_line)
      else
        logger.error("command", "Cannot send selection from unnamed buffer")
      end
    else
      logger.error("command", "No visual selection found")
    end
  end

  vim.api.nvim_create_user_command("ClaudeCodeSend", unified_send_handler, {
    desc = "Send current visual selection as an at_mention to Claude Code (supports tree visual selection)",
    range = true,
  })

  -- Tree explorer integration
  local function get_tree_visual_selection()
    local ft = vim.bo.filetype

    if ft == "neo-tree" then
      local neo_tree = require("neo-tree.sources.manager")
      local renderer = require("neo-tree.ui.renderer")
      local neo_tree_state = neo_tree.get_state("filesystem")

      if neo_tree_state then
        return renderer.get_nodes(neo_tree_state.winid, neo_tree_state.tree:get_nodes())
      end
    elseif ft == "oil" then
      local oil = require("oil")
      local selection = oil.get_cursor_entry()
      if selection then
        local dir = oil.get_current_dir()
        if dir and selection.name then
          return { dir .. selection.name }
        end
      end
    elseif ft == "NvimTree" then
      local api = require("nvim-tree.api")
      local node = api.tree.get_node_under_cursor()
      if node then
        return { node.absolute_path }
      end
    end

    return {}
  end

  local function unified_tree_add_handler()
    local ft = vim.bo.filetype

    if ft == "neo-tree" or ft == "oil" or ft == "NvimTree" then
      local paths = get_tree_visual_selection()
      if #paths > 0 then
        local init = require("claudecode.init")
        init._add_paths_to_claude(paths, { context = "tree explorer" })
      else
        logger.warn("command", "No files selected in tree explorer")
      end
    else
      logger.error("command", "ClaudeCodeTreeAdd only works in tree explorer windows")
    end
  end

  vim.api.nvim_create_user_command("ClaudeCodeTreeAdd", unified_tree_add_handler, {
    desc = "Add selected file(s) from tree explorer to Claude Code context (supports visual selection)",
  })

  vim.api.nvim_create_user_command("ClaudeCodeAdd", function(opts)
    if not state.state.server then
      logger.error("command", "ClaudeCodeAdd: Claude Code integration is not running.")
      return
    end

    local args = opts.args and vim.trim(opts.args) or ""

    if args == "" then
      local file_path = vim.api.nvim_buf_get_name(0)
      if file_path and file_path ~= "" then
        local init = require("claudecode.init")
        init._add_paths_to_claude({ file_path }, { context = "current buffer" })
      else
        logger.error("command", "Cannot add unnamed buffer")
      end
    else
      local paths = vim.split(args, "%s+")
      local expanded_paths = {}
      for _, path in ipairs(paths) do
        local expanded = vim.fn.expand(path)
        if expanded and expanded ~= "" then
          table.insert(expanded_paths, expanded)
        end
      end

      if #expanded_paths > 0 then
        local init = require("claudecode.init")
        init._add_paths_to_claude(expanded_paths, { context = "command argument" })
      else
        logger.error("command", "No valid paths provided")
      end
    end
  end, {
    desc = "Add file(s) to Claude Code context",
    nargs = "*",
    complete = "file",
  })

  -- Terminal commands
  local function setup_terminal_commands()
    vim.api.nvim_create_user_command("ClaudeCode", function(opts)
      local current_mode = vim.fn.mode()
      if current_mode == "v" or current_mode == "V" or current_mode == "\22" then
        unified_send_handler(opts)
      else
        terminal.simple_toggle()
      end
    end, {
      desc = "Toggle Claude Code terminal or send visual selection",
      range = true,
    })

    vim.api.nvim_create_user_command("ClaudeCodeFocus", function(opts)
      local current_mode = vim.fn.mode()
      if current_mode == "v" or current_mode == "V" or current_mode == "\22" then
        unified_send_handler(opts)
      else
        terminal.focus_toggle()
      end
    end, {
      desc = "Focus toggle Claude Code terminal or send visual selection",
      range = true,
    })

    vim.api.nvim_create_user_command("ClaudeCodeOpen", function(opts)
      local cmd_args = opts.args and opts.args ~= "" and opts.args or nil
      terminal.open({}, cmd_args)
    end, {
      desc = "Open Claude Code terminal",
      nargs = "?",
    })

    vim.api.nvim_create_user_command("ClaudeCodeClose", function()
      terminal.close()
    end, {
      desc = "Close Claude Code terminal",
    })

    vim.api.nvim_create_user_command("ClaudeCodeTmux", function(opts)
      local tmux_provider = require("claudecode.terminal.tmux")
      if not tmux_provider.is_available() then
        logger.error("command", "Tmux provider is not available")
        return
      end

      local cmd_args = opts.args and opts.args ~= "" and opts.args or nil

      -- Set tmux as provider and open
      local original_provider = state.state.config.terminal and state.state.config.terminal.provider
      if not state.state.config.terminal then
        state.state.config.terminal = {}
      end
      state.state.config.terminal.provider = "tmux"

      terminal.setup(state.state.config.terminal or {})
      terminal.open({}, cmd_args)

      -- Restore original provider
      if original_provider then
        state.state.config.terminal.provider = original_provider
      end
    end, {
      desc = "Open Claude Code in tmux pane",
      nargs = "?",
    })
  end

  setup_terminal_commands()

  -- Diff commands
  vim.api.nvim_create_user_command("ClaudeCodeDiffAccept", function()
    local diff = require("claudecode.diff")
    diff.accept_current_diff()
  end, {
    desc = "Accept current diff changes",
  })

  vim.api.nvim_create_user_command("ClaudeCodeDiffDeny", function()
    local diff = require("claudecode.diff")
    diff.deny_current_diff()
  end, {
    desc = "Deny/reject current diff changes",
  })

  -- Feature toggle commands
  vim.api.nvim_create_user_command("ClaudeCodeToggleFollowChanges", function()
    if state.state.config then
      state.state.config.follow_file_changes = not state.state.config.follow_file_changes
      local status = state.state.config.follow_file_changes and "enabled" or "disabled"
      logger.info("command", "Follow file changes " .. status)
    else
      logger.error("command", "Plugin not initialized")
    end
  end, {
    desc = "Toggle follow_file_changes feature",
  })

  -- Utility commands
  vim.api.nvim_create_user_command("ClaudeCodeShowLog", function()
    local log_path = logger.get_log_file_path()
    if log_path then
      vim.cmd("edit " .. vim.fn.fnameescape(log_path))
    else
      logger.error("command", "Log file path not available")
    end
  end, {
    desc = "Open Claude Code log file",
  })
end

return M
