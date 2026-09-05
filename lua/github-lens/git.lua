---@class GitHubLens.Git
local M = {}

---Get the top-level root directory of the current git repository.
---@param cwd_or_cb? string|fun(err: string|nil, root: string|nil) Directory or callback
---@param maybe_cb? fun(err: string|nil, root: string|nil) Callback if cwd was passed
function M.get_repo_root(cwd_or_cb, maybe_cb)
  ---@type string|nil
  local cwd
  ---@type fun(err: string|nil, root: string|nil)
  local callback

  if type(cwd_or_cb) == "function" then
    callback = cwd_or_cb
    cwd = nil
  else
    cwd = cwd_or_cb
    callback = maybe_cb or function() end
  end

  vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true, cwd = cwd }, function(out)
    if out.code ~= 0 then
      local err = (out.stderr and out.stderr ~= "") and vim.trim(out.stderr) or "Not a git repository"
      vim.schedule(function()
        callback(err, nil)
      end)
      return
    end

    local root = vim.trim(out.stdout or "")
    vim.schedule(function()
      callback(nil, root)
    end)
  end)
end

---Get the active Git branch name.
---@param cwd_or_cb? string|fun(err: string|nil, branch: string|nil) Directory or callback
---@param maybe_cb? fun(err: string|nil, branch: string|nil) Callback if cwd was passed
function M.get_current_branch(cwd_or_cb, maybe_cb)
  ---@type string|nil
  local cwd
  ---@type fun(err: string|nil, branch: string|nil)
  local callback

  if type(cwd_or_cb) == "function" then
    callback = cwd_or_cb
    cwd = nil
  else
    cwd = cwd_or_cb
    callback = maybe_cb or function() end
  end

  vim.system({ "git", "branch", "--show-current" }, { text = true, cwd = cwd }, function(out)
    if out.code ~= 0 then
      local err = (out.stderr and out.stderr ~= "") and vim.trim(out.stderr) or "Failed to determine branch"
      vim.schedule(function()
        callback(err, nil)
      end)
      return
    end

    local branch = vim.trim(out.stdout or "")
    vim.schedule(function()
      callback(nil, branch)
    end)
  end)
end

---Fetch the active GitHub pull request context for the current branch.
---@param cwd_or_cb? string|fun(err: string|nil, ctx: GitHubLens.PRContext|nil) Directory or callback
---@param maybe_cb? fun(err: string|nil, ctx: GitHubLens.PRContext|nil) Callback if cwd was passed
function M.get_pr_context(cwd_or_cb, maybe_cb)
  ---@type string|nil
  local cwd
  ---@type fun(err: string|nil, ctx: GitHubLens.PRContext|nil)
  local callback

  if type(cwd_or_cb) == "function" then
    callback = cwd_or_cb
    cwd = nil
  else
    cwd = cwd_or_cb
    callback = maybe_cb or function() end
  end

  local cmd = {
    "gh",
    "pr",
    "view",
    "--json",
    "number,title,url,headRefName,baseRefName",
  }

  vim.system(cmd, { text = true, cwd = cwd }, function(out)
    if out.code ~= 0 then
      local err = (out.stderr and out.stderr ~= "") and vim.trim(out.stderr)
        or "No pull request found for current branch"
      vim.schedule(function()
        callback(err, nil)
      end)
      return
    end

    local ok, decoded = pcall(vim.json.decode, out.stdout or "")
    if not ok or type(decoded) ~= "table" then
      local parse_err = "Failed to parse PR context: " .. tostring(decoded)
      vim.schedule(function()
        callback(parse_err, nil)
      end)
      return
    end

    ---@type GitHubLens.PRContext
    local ctx = {
      number = decoded.number,
      title = decoded.title or "",
      url = decoded.url or "",
      head_ref_name = decoded.headRefName or "",
      base_ref_name = decoded.baseRefName or "",
    }

    vim.schedule(function()
      callback(nil, ctx)
    end)
  end)
end

return M
