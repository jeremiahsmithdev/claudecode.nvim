--- Utils module aggregator for claudecode.nvim
-- Provides convenient access to all utility modules.
local M = {}

-- Lazy-load utility modules
M.window = require("claudecode.utils.window")
M.file = require("claudecode.utils.file")

-- Convenience exports for commonly used functions
M.find_main_editor_window = M.window.find_main_editor_window
M.is_editor_window = M.window.is_editor_window
M.detect_filetype = M.file.detect_filetype
M.create_temp_file = M.file.create_temp_file
M.cleanup_temp_file = M.file.cleanup_temp_file

return M
