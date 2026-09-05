---@class GitHubLens.ChecksUI
local M = {}

---@type integer|nil
M._win = nil
---@type integer|nil
M._buf = nil
---@type integer|nil
M._prev_win = nil

local checks_ns = vim.api.nvim_create_namespace("github_lens_checks_ui")

---Close the checks and status window if open.
function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
  end
  M._win = nil
  M._buf = nil
  if M._prev_win and vim.api.nvim_win_is_valid(M._prev_win) then
    pcall(vim.api.nvim_set_current_win, M._prev_win)
  end
  M._prev_win = nil
end

---Check if the status window is currently open.
---@return boolean
function M.is_open()
  return M._win ~= nil and vim.api.nvim_win_is_valid(M._win)
end

---Filter checks according to configuration (default: hide SUCCESS, show all else).
---@param all_checks GitHubLens.Check[]
---@param cfg? GitHubLens.Config|table
---@return GitHubLens.Check[]
function M.filter_checks(all_checks, cfg)
  local checks_cfg = (cfg and cfg.checks) or {}
  local show_success = checks_cfg.show_success == true
  local custom_filter = checks_cfg.filter

  local filtered = {}
  for _, check in ipairs(all_checks) do
    local keep = true

    -- Default: do not show SUCCESS unless show_success is true
    if not show_success and check.conclusion == "SUCCESS" then
      keep = false
    end

    if keep and custom_filter then
      if type(custom_filter) == "function" then
        keep = custom_filter(check)
      elseif type(custom_filter) == "table" then
        local found = false
        for _, allowed in ipairs(custom_filter) do
          local target = check.conclusion or check.status
          if string.upper(allowed) == string.upper(target) then
            found = true
            break
          end
        end
        keep = found
      end
    end

    if keep then
      table.insert(filtered, check)
    end
  end

  return filtered
end

---Get tag label and highlight group for a check.
---@param check GitHubLens.Check
---@return string tag, string hl_group
local function get_check_tag_and_hl(check)
  if check.conclusion == "SUCCESS" then
    return "[PASS]", "DiagnosticOk"
  elseif check.conclusion == "CANCELLED" then
    return "[CANC]", "DiagnosticWarn"
  elseif check.conclusion == "SKIPPED" or check.conclusion == "NEUTRAL" then
    return "[SKIP]", "Comment"
  elseif check.conclusion == "FAILURE" or check.conclusion == "START_UP_FAILURE" or check.conclusion == "TIMED_OUT" then
    return "[FAIL]", "DiagnosticError"
  elseif check.conclusion == "ACTION_REQUIRED" then
    return "[ACTN]", "DiagnosticWarn"
  else
    -- PENDING, IN_PROGRESS, QUEUED, WAITING
    return "[WAIT]", "DiagnosticWarn"
  end
end

---Open or update the Neogit-style status buffer in a bottom horizontal split.
---@param checks GitHubLens.Check[]
---@param ctx? GitHubLens.PRContext
---@param comments? GitHubLens.Comment[]
---@param config? GitHubLens.Config|table
---@param repo_root? string
function M.open(checks, ctx, comments, config, repo_root)
  checks = checks or {}
  comments = comments or {}

  local displayed_checks = M.filter_checks(checks, config)

  local lines = {}
  ---@type table<integer, { type: "url", url: string } | { type: "jump", path: string, line: integer }>
  local line_actions = {}
  ---@type table<integer, { col_start: integer, col_end: integer, hl: string }[]>
  local hl_rows = {}

  local function add_line(text, highlights, action)
    table.insert(lines, text)
    local idx = #lines
    if highlights and #highlights > 0 then
      hl_rows[idx] = highlights
    end
    if action then
      line_actions[idx] = action
    end
  end

  -- 1. PR Header Section
  if ctx then
    local pr_header =
      string.format("PR #%d: %s (%s -> %s)", ctx.number, ctx.title, ctx.head_ref_name, ctx.base_ref_name)
    add_line(pr_header, { { col_start = 0, col_end = #pr_header, hl = "Title" } })

    if ctx.url and ctx.url ~= "" then
      local url_line = "  " .. ctx.url
      add_line(url_line, { { col_start = 2, col_end = #url_line, hl = "Underlined" } }, { type = "url", url = ctx.url })
    end
  else
    add_line("GitHub Lens: No active PR context", { { col_start = 0, col_end = -1, hl = "Title" } })
  end

  add_line("")

  -- 2. CI Checks Section
  local checks_header
  if #displayed_checks == #checks then
    checks_header = string.format("CI Checks (%d)", #displayed_checks)
  else
    checks_header = string.format("CI Checks (%d displayed, %d total)", #displayed_checks, #checks)
  end
  add_line(checks_header, { { col_start = 0, col_end = #checks_header, hl = "Special" } })

  local sep = string.rep("─", 68)
  add_line(sep, { { col_start = 0, col_end = #sep, hl = "FloatBorder" } })

  if #displayed_checks == 0 then
    if #checks > 0 then
      add_line(string.format("  ✔ All %d checks passed (SUCCESS hidden by default).", #checks), {
        { col_start = 2, col_end = 5, hl = "DiagnosticOk" },
      })
    else
      add_line("  ✔ No checks reported for this pull request.", {
        { col_start = 2, col_end = 5, hl = "DiagnosticOk" },
      })
    end
  else
    for _, check in ipairs(displayed_checks) do
      local tag, tag_hl = get_check_tag_and_hl(check)
      local wf = (check.workflow ~= "" and check.workflow ~= check.name) and string.format(" (%s)", check.workflow)
        or ""
      local check_line = string.format("  %s %s%s", tag, check.name, wf)
      local action = (check.details_url and check.details_url ~= "") and { type = "url", url = check.details_url }
        or nil

      add_line(check_line, { { col_start = 2, col_end = 2 + #tag, hl = tag_hl } }, action)

      if check.details_url and check.details_url ~= "" then
        local link_line = string.format("         Link: %s", check.details_url)
        add_line(link_line, {
          { col_start = 9, col_end = 15, hl = "Comment" },
          { col_start = 15, col_end = #link_line, hl = "Underlined" },
        }, { type = "url", url = check.details_url })
      end
    end
  end

  add_line("")

  -- 3. Unresolved Review Comments Section
  local comments_header = string.format("Unresolved Review Comments (%d)", #comments)
  add_line(comments_header, { { col_start = 0, col_end = #comments_header, hl = "Special" } })
  add_line(sep, { { col_start = 0, col_end = #sep, hl = "FloatBorder" } })

  if #comments == 0 then
    add_line("  ✔ No unresolved review comments!", {
      { col_start = 2, col_end = 5, hl = "DiagnosticOk" },
    })
  else
    -- Group comments by file
    local by_file = {}
    local file_order = {}
    for _, c in ipairs(comments) do
      if not by_file[c.path] then
        by_file[c.path] = {}
        table.insert(file_order, c.path)
      end
      table.insert(by_file[c.path], c)
    end

    for _, path in ipairs(file_order) do
      local file_comments = by_file[path]
      for _, c in ipairs(file_comments) do
        local file_line = string.format("  📍 %s:%d", c.path, c.line)
        local jump_action = { type = "jump", path = c.path, line = c.line }
        add_line(file_line, { { col_start = 2, col_end = #file_line, hl = "Tag" } }, jump_action)

        local author_line = string.format("     💬 @%s:", c.author)
        add_line(author_line, { { col_start = 5, col_end = #author_line, hl = "DiagnosticSignInfo" } }, jump_action)

        local body_lines = vim.split(c.body:gsub("\r\n", "\n"), "\n", { plain = true })
        for _, bl in ipairs(body_lines) do
          add_line("        " .. bl, nil, jump_action)
        end
        add_line("")
      end
    end
  end

  -- 4. Footer Section
  add_line(sep, { { col_start = 0, col_end = #sep, hl = "FloatBorder" } })
  local help_line = "[<CR>] Jump to code / Open URL  │  [r] Refresh  │  [q] Close"
  add_line(help_line, { { col_start = 0, col_end = #help_line, hl = "Comment" } })

  -- Setup buffer
  local buf = M._buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "github-lens"
    M._buf = buf
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply syntax highlights via extmarks
  vim.api.nvim_buf_clear_namespace(buf, checks_ns, 0, -1)
  for row_idx, hls in pairs(hl_rows) do
    for _, hl_info in ipairs(hls) do
      vim.api.nvim_buf_set_extmark(buf, checks_ns, row_idx - 1, hl_info.col_start, {
        end_col = hl_info.col_end == -1 and #lines[row_idx] or hl_info.col_end,
        hl_group = hl_info.hl,
      })
    end
  end

  -- Determine window placement (defaults to bottom 30% horizontal split)
  local height_ratio = (config and config.window and config.window.height_ratio) or 0.3
  local height = math.max(6, math.floor(vim.o.lines * height_ratio))

  local win = M._win
  if not win or not vim.api.nvim_win_is_valid(win) then
    local current_win = vim.api.nvim_get_current_win()
    M._prev_win = current_win

    vim.cmd("botright split")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_height(win, height)
    M._win = win

    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = true
    vim.wo[win].wrap = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].spell = false
    vim.wo[win].winfixheight = true
  else
    vim.api.nvim_win_set_height(win, height)
    vim.api.nvim_win_set_buf(win, buf)
  end

  -- Keymaps inside buffer
  local keymap_opts = { buffer = buf, silent = true, nowait = true }

  vim.keymap.set("n", "q", function()
    M.close()
  end, keymap_opts)

  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, keymap_opts)

  vim.keymap.set("n", "r", function()
    require("github-lens").refresh()
  end, keymap_opts)

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local cur_row = cursor[1]
    local action = line_actions[cur_row]

    if not action then
      vim.notify("[github-lens] No action on this line", vim.log.levels.INFO)
      return
    end

    if action.type == "url" then
      vim.ui.open(action.url)
      vim.notify("[github-lens] Opening URL: " .. action.url, vim.log.levels.INFO)
    elseif action.type == "jump" then
      local target_win = M._prev_win
      if not target_win or not vim.api.nvim_win_is_valid(target_win) or target_win == win then
        vim.cmd("wincmd k")
        target_win = vim.api.nvim_get_current_win()
        if target_win == win then
          vim.cmd("aboveleft split")
          target_win = vim.api.nvim_get_current_win()
        end
      end

      vim.api.nvim_set_current_win(target_win)
      local root = repo_root or vim.fn.getcwd()
      local full_path = vim.fs.normalize(root .. "/" .. action.path)
      vim.cmd("edit " .. vim.fn.fnameescape(full_path))
      local line_count = vim.api.nvim_buf_line_count(0)
      local target_line = math.max(1, math.min(action.line, line_count))
      vim.api.nvim_win_set_cursor(target_win, { target_line, 0 })
    end
  end, keymap_opts)
end

---Toggle the status window.
---@param checks GitHubLens.Check[]
---@param ctx? GitHubLens.PRContext
---@param comments? GitHubLens.Comment[]
---@param config? GitHubLens.Config|table
---@param repo_root? string
function M.toggle(checks, ctx, comments, config, repo_root)
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M.close()
  else
    M.open(checks, ctx, comments, config, repo_root)
  end
end

return M
