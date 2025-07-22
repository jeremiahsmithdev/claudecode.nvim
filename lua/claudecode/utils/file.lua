--- File utilities for claudecode.nvim
-- Shared file management functions used across the codebase.
local M = {}

--- Create a temporary file with given content.
-- @param content string The content to write to the file
-- @param filename string Base filename for the temporary file
-- @return string|nil, string|nil The temporary file path and error message
function M.create_temp_file(content, filename)
  local base_dir_cache = vim.fn.stdpath("cache") .. "/claudecode_diffs"
  local mkdir_ok_cache, mkdir_err_cache = pcall(vim.fn.mkdir, base_dir_cache, "p")

  local final_base_dir
  if mkdir_ok_cache then
    final_base_dir = base_dir_cache
  else
    local base_dir_temp = vim.fn.stdpath("cache") .. "/claudecode_diffs_fallback"
    local mkdir_ok_temp, mkdir_err_temp = pcall(vim.fn.mkdir, base_dir_temp, "p")
    if not mkdir_ok_temp then
      local err_to_report = mkdir_err_temp or mkdir_err_cache or "unknown error creating base temp dir"
      return nil, "Failed to create base temporary directory: " .. tostring(err_to_report)
    end
    final_base_dir = base_dir_temp
  end

  local session_id_base = vim.fn.fnamemodify(vim.fn.tempname(), ":t")
    .. "_"
    .. tostring(os.time())
    .. "_"
    .. tostring(math.random(1000, 9999))
  local session_id = session_id_base:gsub("[^A-Za-z0-9_-]", "")
  if session_id == "" then -- Fallback if all characters were problematic, ensuring a directory can be made.
    session_id = "claudecode_session"
  end

  local tmp_session_dir = final_base_dir .. "/" .. session_id
  local mkdir_session_ok, mkdir_session_err = pcall(vim.fn.mkdir, tmp_session_dir, "p")
  if not mkdir_session_ok then
    return nil, "Failed to create temporary session directory: " .. tostring(mkdir_session_err)
  end

  local tmp_file = tmp_session_dir .. "/" .. filename
  local file = io.open(tmp_file, "w")
  if not file then
    return nil, "Failed to create temporary file: " .. tmp_file
  end

  file:write(content)
  file:close()

  return tmp_file, nil
end

--- Clean up temporary files and directories.
-- @param tmp_file string Path to the temporary file to clean up
function M.cleanup_temp_file(tmp_file)
  if tmp_file and vim.fn.filereadable(tmp_file) == 1 then
    local tmp_dir = vim.fn.fnamemodify(tmp_file, ":h")
    if vim.fs and type(vim.fs.remove) == "function" then
      local ok_file, err_file = pcall(vim.fs.remove, tmp_file)
      if not ok_file then
        vim.notify(
          "ClaudeCode: Error removing temp file " .. tmp_file .. ": " .. tostring(err_file),
          vim.log.levels.WARN
        )
      end

      local ok_dir, err_dir = pcall(vim.fs.remove, tmp_dir)
      if not ok_dir then
        vim.notify(
          "ClaudeCode: Error removing temp directory " .. tmp_dir .. ": " .. tostring(err_dir),
          vim.log.levels.INFO
        )
      end
    else
      local reason = "vim.fs.remove is not a function"
      if not vim.fs then
        reason = "vim.fs is nil"
      end
      vim.notify(
        "ClaudeCode: Cannot perform standard cleanup: "
          .. reason
          .. ". Affected file: "
          .. tmp_file
          .. ". Please check your Neovim setup or report this issue.",
        vim.log.levels.ERROR
      )
      -- Fallback to os.remove for the file.
      local os_ok, os_err = pcall(os.remove, tmp_file)
      if not os_ok then
        vim.notify(
          "ClaudeCode: Fallback os.remove also failed for file " .. tmp_file .. ": " .. tostring(os_err),
          vim.log.levels.ERROR
        )
      end
    end
  end
end

--- Detect filetype from a path or existing buffer (best-effort).
-- @param path string File path to detect filetype for
-- @param buf number|nil Optional buffer handle to check for existing filetype
-- @return string|nil The detected filetype, or nil if unable to detect
function M.detect_filetype(path, buf)
  -- 1) Try Neovim's builtin matcher if available (>=0.10)
  if vim.filetype and type(vim.filetype.match) == "function" then
    local ok, ft = pcall(vim.filetype.match, { filename = path })
    if ok and ft and ft ~= "" then
      return ft
    end
  end

  -- 2) Try reading from existing buffer
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local ft = vim.api.nvim_buf_get_option(buf, "filetype")
    if ft and ft ~= "" then
      return ft
    end
  end

  -- 3) Fallback to simple extension mapping
  local ext = path:match("%.([%w_%-]+)$") or ""
  local simple_map = {
    lua = "lua",
    ts = "typescript",
    js = "javascript",
    jsx = "javascriptreact",
    tsx = "typescriptreact",
    py = "python",
    go = "go",
    rs = "rust",
    c = "c",
    h = "c",
    cpp = "cpp",
    hpp = "cpp",
    md = "markdown",
    sh = "sh",
    zsh = "zsh",
    bash = "bash",
    json = "json",
    yaml = "yaml",
    yml = "yaml",
    toml = "toml",
    xml = "xml",
    html = "html",
    css = "css",
    scss = "scss",
    vim = "vim",
    txt = "text",
  }
  return simple_map[ext]
end

--- Check if a file exists and is readable.
-- @param file_path string Path to the file to check
-- @return boolean true if file exists and is readable
function M.file_exists(file_path)
  return vim.fn.filereadable(file_path) == 1
end

--- Get file modification time.
-- @param file_path string Path to the file
-- @return number Modification time as unix timestamp, or 0 if file doesn't exist
function M.get_file_mtime(file_path)
  if not M.file_exists(file_path) then
    return 0
  end
  return vim.fn.getftime(file_path)
end

--- Expand file path using vim.fn.expand.
-- @param file_path string Path to expand (can contain ~, $HOME, etc.)
-- @return string Expanded absolute path
function M.expand_path(file_path)
  return vim.fn.expand(file_path)
end

return M
