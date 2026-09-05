---@class GitHubLens.Comments
local M = {}

local ns_id = vim.api.nvim_create_namespace("github_lens_comments")

---@type GitHubLens.Comment[]
M._cached_comments = {}
---@type string|nil
M._repo_root = nil
---@type GitHubLens.Config
M._config = {
  virtual_lines = true,
  comment_hl = "DiagnosticSignInfo",
  keymaps = {},
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

  local bar = vim.trim(prefix)
  local continuation_prefix
  if bar == "│" or bar == "|" or bar == "┃" then
    continuation_prefix = "│   "
  else
    continuation_prefix = string.rep(" ", vim.fn.strdisplaywidth(prefix) + 2)
  end

  if config and config.virtual_lines then
    local clean_body = comment.body:gsub("\r\n", "\n")
    local body_lines = vim.split(clean_body, "\n", { plain = true })

    local header = string.format("%s@%s: ", prefix, comment.author)
    table.insert(virt_lines, {
      { header, comment_hl },
      { body_lines[1] or "", "NormalFloat" },
    })

    for i = 2, #body_lines do
      table.insert(virt_lines, {
        { continuation_prefix, comment_hl },
        { body_lines[i], "NormalFloat" },
      })
    end
  else
    local single_body = comment.body:gsub("[\r\n]+", " ")
    table.insert(virt_lines, {
      { string.format("%s@%s: ", prefix, comment.author), comment_hl },
      { single_body, "NormalFloat" },
    })
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

  for _, comment in ipairs(M._cached_comments) do
    if buffer_matches_path(bufnr, comment.path, M._repo_root) then
      local target_line = math.max(1, math.min(comment.line or 1, line_count))
      local virt_lines = build_virt_lines(comment, M._config)

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, target_line - 1, 0, {
        virt_lines = virt_lines,
        virt_lines_above = false,
      })
    end
  end
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
