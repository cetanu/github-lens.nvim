---@class GitHubLens.GH
local M = {}

---Return the first usable line number from GitHub's current and original positions.
---JSON null values decode to vim.NIL, which is truthy and therefore cannot be
---handled correctly with `current or original`.
---@param current any
---@param original any
---@return integer
local function review_line(current, original)
  local line = tonumber(current) or tonumber(original) or 1
  return math.max(1, math.floor(line))
end

---Fetch unresolved PR review comments for a pull request via GitHub GraphQL API.
---@param pr_number integer Pull request number
---@param cwd_or_opts? string|table Directory or options table { cwd?: string, owner?: string, repo?: string }
---@param callback fun(err: string|nil, comments: GitHubLens.Comment[]|nil) Async callback
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
          id
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

    ---@type GitHubLens.Comment[]
    local comments = {}

    for _, thread in ipairs(threads) do
      if not thread.isResolved then
        local c_nodes = (thread.comments and thread.comments.nodes) or {}
        local path = thread.path or ""
        local line = review_line(thread.line, thread.originalLine)
        local orig_line = review_line(thread.originalLine, thread.line)

        for _, c in ipairs(c_nodes) do
          ---@type GitHubLens.Comment
          local comment = {
            id = c.id or "",
            thread_id = thread.id or "",
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

    -- GitHub connection order is not a display-order contract. Give each
    -- thread a stable position so its comments cannot be interleaved with a
    -- different thread on the same line, then order comments within it.
    local thread_first = {}
    for _, comment in ipairs(comments) do
      local first = thread_first[comment.thread_id]
      if not first or comment.created_at < first then
        thread_first[comment.thread_id] = comment.created_at
      end
    end

    table.sort(comments, function(a, b)
      if a.path ~= b.path then
        return a.path < b.path
      end
      if a.line ~= b.line then
        return a.line < b.line
      end
      if a.thread_id ~= b.thread_id then
        local a_first = thread_first[a.thread_id] or a.created_at
        local b_first = thread_first[b.thread_id] or b.created_at
        if a_first ~= b_first then
          return a_first < b_first
        end
        return a.thread_id < b.thread_id
      end
      if a.created_at ~= b.created_at then
        return a.created_at < b.created_at
      end
      return a.id < b.id
    end)

    vim.schedule(function()
      callback(nil, comments)
    end)
  end)
end

---Execute a GraphQL mutation through the authenticated GitHub CLI.
---@param mutation string
---@param variables table<string, string>
---@param cwd? string
---@param callback fun(err: string|nil, data: table|nil)
local function execute_mutation(mutation, variables, cwd, callback)
  local cmd = { "gh", "api", "graphql" }
  for name, value in pairs(variables) do
    table.insert(cmd, "-F")
    table.insert(cmd, name .. "=" .. value)
  end
  table.insert(cmd, "-f")
  table.insert(cmd, "query=" .. mutation)

  vim.system(cmd, { text = true, cwd = cwd }, function(out)
    local ok, decoded = pcall(vim.json.decode, out.stdout or "")
    if not ok or type(decoded) ~= "table" then
      local stderr = vim.trim(out.stderr or "")
      local err = stderr ~= "" and stderr or ("Failed to parse GraphQL response: " .. tostring(decoded))
      vim.schedule(function()
        callback(err, nil)
      end)
      return
    end

    if decoded.errors and #decoded.errors > 0 then
      vim.schedule(function()
        callback(decoded.errors[1].message or "GraphQL mutation error", nil)
      end)
      return
    end

    if out.code ~= 0 then
      vim.schedule(function()
        callback("gh api graphql failed with code " .. tostring(out.code), nil)
      end)
      return
    end

    vim.schedule(function()
      callback(nil, decoded.data or {})
    end)
  end)
end

---Reply to an existing pull request review thread via the GitHub CLI.
---@param thread_id string Review thread node ID
---@param body string Reply body
---@param cwd? string
---@param callback fun(err: string|nil)
function M.reply_to_thread(thread_id, body, cwd, callback)
  local mutation = [[
mutation($thread_id: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $thread_id
    body: $body
  }) {
    clientMutationId
  }
}
]]
  execute_mutation(mutation, { thread_id = thread_id, body = body }, cwd, function(err)
    callback(err)
  end)
end

---Resolve a pull request review thread via the GitHub CLI.
---@param thread_id string Review thread node ID
---@param cwd? string
---@param callback fun(err: string|nil)
function M.resolve_thread(thread_id, cwd, callback)
  local mutation = [[
mutation($thread_id: ID!) {
  resolveReviewThread(input: { threadId: $thread_id }) {
    thread { id isResolved }
  }
}
]]
  execute_mutation(mutation, { thread_id = thread_id }, cwd, function(err)
    callback(err)
  end)
end

---Fetch failing and pending CI checks for a pull request via GitHub CLI.
---@param pr_number integer Pull request number
---@param cwd_or_opts? string|table Directory or options table { cwd?: string }
---@param callback fun(err: string|nil, checks: GitHubLens.Check[]|nil) Async callback
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

    ---@type GitHubLens.Check[]
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

      ---@type GitHubLens.Check
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
