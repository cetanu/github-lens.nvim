---@class GitHubLens
local M = {}

local git = require("github-lens.git")
local gh = require("github-lens.gh")
local comments_mod = require("github-lens.comments")
local checks_mod = require("github-lens.checks")

local function status_cache_path()
  return vim.fn.stdpath("state") .. "/github-lens/status.json"
end

---@param repo_root string
---@return GitHubLens.Status|nil
local function load_cached_status(repo_root)
  local ok, lines = pcall(vim.fn.readfile, status_cache_path())
  if not ok or #lines == 0 then
    return nil
  end

  local decoded_ok, cache = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok or type(cache) ~= "table" then
    return nil
  end

  local status = cache[repo_root]
  if type(status) ~= "table" or type(status.context) ~= "table" then
    return nil
  end

  return status
end

---@param status GitHubLens.Status
local function save_cached_status(status)
  local path = status_cache_path()
  local cache_dir = vim.fn.fnamemodify(path, ":h")
  local ok = pcall(vim.fn.mkdir, cache_dir, "p")
  if not ok then
    return
  end

  local read_ok, lines = pcall(vim.fn.readfile, path)
  local cache = {}
  if read_ok and #lines > 0 then
    local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    if decode_ok and type(decoded) == "table" then
      cache = decoded
    end
  end

  cache[status.repo_root] = status
  local encode_ok, encoded = pcall(vim.json.encode, cache)
  if encode_ok then
    pcall(vim.fn.writefile, { encoded }, path)
  end
end

---@type GitHubLens.Config
local default_config = {
  virtual_lines = true,
  comment_hl = "DiagnosticSignInfo",
  symbols = {
    pass = "✔",
    fail = "✖",
    pending = "●",
    cancelled = "⊘",
    skipped = "⊘",
    action_required = "◆",
    comment_prefix = "│ ",
  },
  window = {
    position = "bottom",
    height_ratio = 0.3,
    width_ratio = 0.7,
    border = "single",
  },
  checks = {
    show_success = false,
  },
}

---@type GitHubLens.Config
M.config = vim.deepcopy(default_config)

---@type GitHubLens.State
M.state = {
  context = nil,
  comments = {},
  checks = {},
  repo_root = nil,
  last_status = nil,
}

---Setup github-lens plugin with user options.
---@param opts? table User configuration options
function M.setup(opts)
  if opts then
    local config_opts = vim.deepcopy(opts)
    config_opts.keymaps = nil
    if config_opts.symbols then
      config_opts.symbols.section_open = nil
      config_opts.symbols.section_closed = nil
      config_opts.symbols.file_open = nil
      config_opts.symbols.file_closed = nil
    end
    M.config = vim.tbl_deep_extend("force", default_config, config_opts)
  else
    M.config = vim.deepcopy(default_config)
  end
end

---Fetch PR context, comments, and checks asynchronously and update UI.
function M.refresh()
  local last_status = M.state.last_status
  if last_status then
    checks_mod.open(last_status.checks, last_status.context, last_status.comments, M.config, last_status.repo_root)
  end

  git.get_repo_root(nil, function(root_err, root)
    if root_err or not root then
      vim.notify("[github-lens] " .. (root_err or "Not inside a git repository"), vim.log.levels.ERROR)
      return
    end

    M.state.repo_root = root

    last_status = M.state.last_status
    if not last_status or last_status.repo_root ~= root then
      last_status = load_cached_status(root)
      M.state.last_status = last_status
      if last_status then
        checks_mod.open(last_status.checks, last_status.context, last_status.comments, M.config, root)
      end
    end

    git.get_pr_context(root, function(ctx_err, ctx)
      if ctx_err or not ctx then
        vim.notify("[github-lens] " .. (ctx_err or "No PR context found"), vim.log.levels.WARN)
        M.clear()
        return
      end

      M.state.context = ctx
      vim.notify(string.format("[github-lens] Querying PR #%d: %s", ctx.number, ctx.title), vim.log.levels.INFO)

      local pending = 2
      local function on_complete()
        pending = pending - 1
        if pending == 0 then
          comments_mod.set_comments(M.state.comments, root, M.config)
          M.state.last_status = {
            context = vim.deepcopy(M.state.context),
            comments = vim.deepcopy(M.state.comments),
            checks = vim.deepcopy(M.state.checks),
            repo_root = root,
          }
          save_cached_status(M.state.last_status)
          local c_count = #M.state.comments
          local ch_count = #M.state.checks
          vim.notify(
            string.format(
              "[github-lens] Refreshed: %d unresolved comment(s), %d failing/pending check(s)",
              c_count,
              ch_count
            ),
            vim.log.levels.INFO
          )

          -- Open or update the Neogit-style status split buffer at bottom 30%
          checks_mod.open(M.state.checks, M.state.context, M.state.comments, M.config, root)
        end
      end

      gh.fetch_unresolved_comments(ctx.number, root, function(c_err, comments)
        if c_err then
          vim.notify("[github-lens] Failed to fetch comments: " .. c_err, vim.log.levels.WARN)
          M.state.comments = {}
        else
          M.state.comments = comments or {}
        end
        on_complete()
      end)

      gh.fetch_checks(ctx.number, root, function(ch_err, checks)
        if ch_err then
          vim.notify("[github-lens] Failed to fetch checks: " .. ch_err, vim.log.levels.WARN)
          M.state.checks = {}
        else
          M.state.checks = checks or {}
        end
        on_complete()
      end)
    end)
  end)
end

---Toggle or open the Neogit-style status split window for PR checks and comments.
function M.show_checks()
  checks_mod.toggle(M.state.checks, M.state.context, M.state.comments, M.config, M.state.repo_root)
end

---Alias for show_checks() to toggle status buffer.
function M.status()
  M.show_checks()
end

---Wipe all extmarks, close checks popup, and reset internal state.
function M.clear()
  M.state.context = nil
  M.state.comments = {}
  M.state.checks = {}
  comments_mod.clear()
  checks_mod.clear()
  M.state.last_status = nil
  vim.notify("[github-lens] Cleared comments and checks", vim.log.levels.INFO)
end

---Populate the quickfix list with all cached unresolved PR comments and open it.
function M.quickfix()
  if #M.state.comments == 0 then
    vim.notify("[github-lens] No unresolved comments found", vim.log.levels.INFO)
    return
  end

  local qf_list = {}
  local root = M.state.repo_root or vim.fn.getcwd()
  for _, c in ipairs(M.state.comments) do
    local filename = vim.fs.normalize(root .. "/" .. c.path)
    table.insert(qf_list, {
      filename = filename,
      lnum = c.line,
      col = 1,
      text = string.format("@%s: %s", c.author, c.body:gsub("[\r\n]+", " ")),
      type = "I",
    })
  end

  local title = M.state.context and string.format("PR #%d Comments", M.state.context.number) or "PR Comments"
  vim.fn.setqflist(qf_list, "r")
  vim.fn.setqflist({}, "a", { title = title })
  vim.cmd("copen")
end

return M
