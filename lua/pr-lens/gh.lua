---@class PRLens.GH
local M = {}

---Fetch unresolved PR review comments for a pull request via GitHub GraphQL API.
---@param pr_number integer Pull request number
---@param cwd_or_opts? string|table Directory or options table { cwd?: string, owner?: string, repo?: string }
---@param callback fun(err: string|nil, comments: PRLens.Comment[]|nil) Async callback
function M.fetch_unresolved_comments(pr_number, cwd_or_opts, callback)
  local cwd
  local owner = "{owner}"
  local repo = "{repo}"

  if type(cwd_or_opts) == "table" then
    cwd = cwd_or_opts.cwd
    if cwd_or_opts.owner and cwd_or_opts.owner ~= "" then
      owner = cwd_or_opts.owner
    end
    if cwd_or_opts.repo and cwd_or_opts.repo ~= "" then
      repo = cwd_or_opts.repo
    end
  elseif type(cwd_or_opts) == "string" then
    cwd = cwd_or_opts
  end

  local query = [[
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          path
          line
          originalLine
          comments(first: 50) {
            nodes {
              id
              author { login }
              body
              createdAt
              url
            }
          }
        }
      }
    }
  }
}
]]

  local cmd = {
    "gh",
    "api",
    "graphql",
    "-F",
    "owner=" .. owner,
    "-F",
    "repo=" .. repo,
    "-F",
    "pr=" .. tostring(pr_number),
    "-f",
    "query=" .. query,
  }

  vim.system(cmd, { text = true, cwd = cwd }, function(out)
    if out.code ~= 0 and (not out.stdout or out.stdout == "") then
      local err = (out.stderr and out.stderr ~= "") and vim.trim(out.stderr)
        or ("gh api graphql failed with code " .. tostring(out.code))
      vim.schedule(function()
        callback(err, nil)
      end)
      return
    end

    local ok, decoded = pcall(vim.json.decode, out.stdout or "")
    if not ok or type(decoded) ~= "table" then
      local parse_err = "Failed to parse GraphQL response: " .. tostring(decoded)
      vim.schedule(function()
        callback(parse_err, nil)
      end)
      return
    end

    if decoded.errors and #decoded.errors > 0 then
      local msg = decoded.errors[1].message or "GraphQL query error"
      vim.schedule(function()
        callback(msg, nil)
      end)
      return
    end

    local data = decoded.data
    if not data or not data.repository or not data.repository.pullRequest then
      vim.schedule(function()
        callback("No pull request found in GraphQL response", nil)
      end)
      return
    end

    local threads = (data.repository.pullRequest.reviewThreads and data.repository.pullRequest.reviewThreads.nodes)
      or {}

    ---@type PRLens.Comment[]
    local comments = {}

    for _, thread in ipairs(threads) do
      if not thread.isResolved then
        local c_nodes = (thread.comments and thread.comments.nodes) or {}
        local path = thread.path or ""
        local raw_line = thread.line or thread.originalLine or 1
        local raw_orig = thread.originalLine or thread.line or 1
        local line = math.floor(tonumber(raw_line) or 1)
        local orig_line = math.floor(tonumber(raw_orig) or 1)

        for _, c in ipairs(c_nodes) do
          ---@type PRLens.Comment
          local comment = {
            id = c.id or "",
            author = (c.author and c.author.login) or "ghost",
            body = c.body or "",
            path = path,
            line = line,
            original_line = orig_line,
            is_resolved = false,
            created_at = c.createdAt or "",
            url = c.url or "",
          }
          table.insert(comments, comment)
        end
      end
    end

    vim.schedule(function()
      callback(nil, comments)
    end)
  end)
end

---Fetch failing and pending CI checks for a pull request via GitHub CLI.
---@param pr_number integer Pull request number
---@param cwd_or_opts? string|table Directory or options table { cwd?: string }
---@param callback fun(err: string|nil, checks: PRLens.Check[]|nil) Async callback
function M.fetch_checks(pr_number, cwd_or_opts, callback)
  local cwd
  if type(cwd_or_opts) == "table" then
    cwd = cwd_or_opts.cwd
  elseif type(cwd_or_opts) == "string" then
    cwd = cwd_or_opts
  end

  local cmd = {
    "gh",
    "pr",
    "checks",
    tostring(pr_number),
    "--json",
    "name,state,bucket,workflow,link",
  }

  vim.system(cmd, { text = true, cwd = cwd }, function(out)
    local stdout = vim.trim(out.stdout or "")
    local stderr = vim.trim(out.stderr or "")

    -- Check if no checks were reported for branch
    if
      stdout == "" and (string.find(stderr, "no checks reported") or string.find(stderr, "no pull requests found"))
    then
      vim.schedule(function()
        callback(nil, {})
      end)
      return
    end

    local ok, raw_checks = pcall(vim.json.decode, stdout)
    if not ok or type(raw_checks) ~= "table" then
      if out.code ~= 0 then
        local err = stderr ~= "" and stderr or ("gh pr checks failed with code " .. tostring(out.code))
        vim.schedule(function()
          callback(err, nil)
        end)
        return
      end
      vim.schedule(function()
        callback("Failed to parse checks JSON: " .. tostring(raw_checks), nil)
      end)
      return
    end

    ---@type PRLens.Check[]
    local all_checks = {}

    for _, item in ipairs(raw_checks) do
      local bucket = string.lower(item.bucket or "")
      local st_upper = string.upper(item.state or "")

      ---@type CheckStatus
      local status = "COMPLETED"
      ---@type CheckConclusion
      local conclusion = nil

      if
        bucket == "pending"
        or st_upper == "IN_PROGRESS"
        or st_upper == "QUEUED"
        or st_upper == "WAITING"
        or st_upper == "PENDING"
      then
        if st_upper == "IN_PROGRESS" or st_upper == "QUEUED" or st_upper == "WAITING" or st_upper == "PENDING" then
          status = st_upper
        else
          status = "PENDING"
        end
        conclusion = nil
      else
        status = "COMPLETED"
        if st_upper == "SUCCESS" or bucket == "pass" then
          conclusion = "SUCCESS"
        elseif st_upper == "CANCELLED" or bucket == "cancel" then
          conclusion = "CANCELLED"
        elseif st_upper == "SKIPPED" or bucket == "skipping" then
          conclusion = "SKIPPED"
        elseif st_upper == "NEUTRAL" then
          conclusion = "NEUTRAL"
        elseif st_upper == "TIMED_OUT" then
          conclusion = "TIMED_OUT"
        elseif st_upper == "START_UP_FAILURE" then
          conclusion = "START_UP_FAILURE"
        elseif st_upper == "ACTION_REQUIRED" then
          conclusion = "ACTION_REQUIRED"
        elseif st_upper == "STALE" then
          conclusion = "STALE"
        else
          conclusion = "FAILURE"
        end
      end

      ---@type PRLens.Check
      local check = {
        name = item.name or "",
        workflow = item.workflow or "",
        status = status,
        conclusion = conclusion,
        details_url = item.link or "",
      }
      table.insert(all_checks, check)
    end

    vim.schedule(function()
      callback(nil, all_checks)
    end)
  end)
end

return M
