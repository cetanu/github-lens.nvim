---@class GitHubLens.Comments
local M = {}

local ns_id = vim.api.nvim_create_namespace("github_lens_comments")

---@type GitHubLens.Comment[]
M._cached_comments = {}
---@type table<string, boolean>
---@type string|nil
M._repo_root = nil
---@type GitHubLens.Config
M._config = {
  virtual_lines = true,
  comment_hl = "DiagnosticSignInfo",
}

---Get the comments namespace ID.
---@return integer
function M.get_namespace()
  return ns_id
end

---Normalize a path and strip macOS /private prefix if present.
---@param p string
---@return string
local function normalize_path(p)
  local norm = vim.fs.normalize(p)
  if vim.startswith(norm, "/private/") then
    norm = norm:sub(9)
  end
  return norm
end

---Check if a buffer matches a comment path.
---@param bufnr integer
---@param comment_path string
---@param repo_root string|nil
---@return boolean
local function buffer_matches_path(bufnr, comment_path, repo_root)
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  if buf_name == "" then
    return false
  end

  local norm_buf = normalize_path(buf_name)
  local norm_comment = normalize_path(comment_path)

  if repo_root and repo_root ~= "" then
    local clean_root = normalize_path(repo_root)
    local target_path = normalize_path(clean_root .. "/" .. norm_comment)
    if norm_buf == target_path then
      return true
    end

    local rel = vim.fs.relpath(clean_root, norm_buf)
    if rel and normalize_path(rel) == norm_comment then
      return true
    end

    -- Realpath check in case of symlinks
    local real_buf = vim.uv.fs_realpath(buf_name)
    local real_target = vim.uv.fs_realpath(repo_root .. "/" .. comment_path)
    if real_buf and real_target and real_buf == real_target then
      return true
    end
  else
    if norm_buf == norm_comment or vim.endswith(norm_buf, "/" .. norm_comment) then
      return true
    end
  end

  return false
end

---Build virtual line structures for a comment.
---@param comment GitHubLens.Comment
---@param config GitHubLens.Config
---@return table[] virt_lines
local function build_virt_lines(comment, config)
  local comment_hl = (config and config.comment_hl) or "DiagnosticSignInfo"
  local prefix = (config and config.symbols and config.symbols.comment_prefix) or "│ "
  local virt_lines = {}
  local max_width = math.max(20, (config and config.comment_width) or 80)

  local bar = vim.trim(prefix)
  local continuation_prefix
  if bar == "│" or bar == "|" or bar == "┃" then
    continuation_prefix = "│   "
  else
    continuation_prefix = string.rep(" ", vim.fn.strdisplaywidth(prefix) + 2)
  end

  ---Wrap a display line without splitting words unless a word is too long.
  ---@param text string
  ---@param width integer
  ---@return string[]
  local function wrap_line(text, width)
    if width <= 0 or vim.fn.strdisplaywidth(text) <= width then
      return { text }
    end

    local result = {}
    local current = ""
    for word in text:gmatch("%S+") do
      local candidate = current == "" and word or (current .. " " .. word)
      if vim.fn.strdisplaywidth(candidate) <= width then
        current = candidate
      else
        if current ~= "" then
          table.insert(result, current)
        end
        while vim.fn.strdisplaywidth(word) > width do
          local chunk = vim.fn.strcharpart(word, 0, width)
          table.insert(result, chunk)
          word = vim.fn.strcharpart(word, vim.fn.strchars(chunk))
        end
        current = word
      end
    end
    if current ~= "" or #result == 0 then
      table.insert(result, current)
    end
    return result
  end

  local function add_wrapped_body_lines(body, prefix_text)
    local available = math.max(1, max_width - vim.fn.strdisplaywidth(prefix_text))
    for _, logical_line in ipairs(vim.split(body, "\n", { plain = true })) do
      if vim.trim(logical_line) ~= "" then
        for _, wrapped in ipairs(wrap_line(logical_line, available)) do
          table.insert(virt_lines, {
            { prefix_text, comment_hl },
            { wrapped, "NormalFloat" },
          })
          prefix_text = continuation_prefix
          available = math.max(1, max_width - vim.fn.strdisplaywidth(prefix_text))
        end
      end
    end
  end

  if config and config.virtual_lines then
    local clean_body = comment.body:gsub("\r\n", "\n")
    local header = string.format("%s@%s: ", prefix, comment.author)
    add_wrapped_body_lines(clean_body, header)
  else
    local single_body = comment.body:gsub("[\r\n]+", " ")
    add_wrapped_body_lines(single_body, string.format("%s@%s: ", prefix, comment.author))
  end

  local preview_lines = (config and config.comment_preview_lines) or 3
  if #virt_lines > preview_lines then
    local hidden_count = #virt_lines - preview_lines
    local preview = {}
    for i = 1, preview_lines do
      table.insert(preview, virt_lines[i])
    end
    table.insert(preview, {
      { continuation_prefix, comment_hl },
      { string.format("… %d lines hidden", hidden_count), "Comment" },
    })
    virt_lines = preview
  end

  return virt_lines
end

---Render comments for a specific buffer.
---@param bufnr integer
function M.render_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  -- Clear previous marks for this buffer
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  if #M._cached_comments == 0 then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return
  end

  local lines_with_comments = {}
  local line_order = {}
  for _, comment in ipairs(M._cached_comments) do
    if buffer_matches_path(bufnr, comment.path, M._repo_root) then
      local target_line = math.max(1, math.min(comment.line or 1, line_count))
      if not lines_with_comments[target_line] then
        lines_with_comments[target_line] = {}
        table.insert(line_order, target_line)
      end
      local comment_lines = build_virt_lines(comment, M._config)
      for _, virt_line in ipairs(comment_lines) do
        table.insert(lines_with_comments[target_line], virt_line)
      end
    end
  end

  for _, target_line in ipairs(line_order) do
    local virt_lines = lines_with_comments[target_line]
    if virt_lines then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, target_line - 1, 0, {
        virt_lines = virt_lines,
        virt_lines_above = false,
      })
    end
  end
end

---Find the unresolved comment at a buffer line.
---@param bufnr integer
---@param line integer 1-based buffer line
---@return GitHubLens.Comment|nil
function M.find_at_cursor(bufnr, line)
  for _, comment in ipairs(M._cached_comments) do
    if comment.line == line and buffer_matches_path(bufnr, comment.path, M._repo_root) then
      return comment
    end
  end
  return nil
end

---Store comments and render into all currently loaded buffers.
---@param comments GitHubLens.Comment[]
---@param repo_root? string
---@param config? GitHubLens.Config
function M.set_comments(comments, repo_root, config)
  M._cached_comments = comments or {}
  if repo_root then
    M._repo_root = repo_root
  end
  if config then
    M._config = config
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.render_buffer(bufnr)
    end
  end
end

---Clear extmarks and optionally cached comments.
---@param bufnr? integer If provided, clears only that buffer; otherwise clears all loaded buffers and wipes cache
function M.clear(bufnr)
  if bufnr then
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end
  else
    M._cached_comments = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_is_loaded(b) then
        vim.api.nvim_buf_clear_namespace(b, ns_id, 0, -1)
      end
    end
  end
end

---Setup autocmd to render comments on BufReadPost.
function M.setup_autocmds()
  local augroup = vim.api.nvim_create_augroup("github_lens_comments", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    callback = function(args)
      M.render_buffer(args.buf)
    end,
    desc = "GitHub Lens: Render comments on buffer read",
  })
end

M.setup_autocmds()

return M
