---@class GitHubLens.ChecksUI
local M = {}

---@type integer|nil
M._win = nil
---@type integer|nil
M._buf = nil
---@type integer|nil
M._prev_win = nil
---@type integer|nil
M._help_win = nil

---@type GitHubLens.Check[]
M._cached_checks = {}
---@type GitHubLens.PRContext|nil
M._cached_ctx = nil
---@type GitHubLens.Comment[]
M._cached_comments = {}
---@type GitHubLens.Config|table
M._cached_config = {}
---@type string|nil
M._cached_repo_root = nil

---@type table<string, boolean>
M._folded_sections = {}
---@type table<string, boolean>
M._folded_files = {}
---@type boolean|nil
M._show_success_override = nil
---@type integer[]
M._action_rows = {}

local checks_ns = vim.api.nvim_create_namespace("github_lens_checks_ui")

local default_symbols = {
  pass = "✔",
  fail = "✖",
  pending = "●",
  cancelled = "⊘",
  skipped = "⊘",
  action_required = "◆",
  comment_prefix = "│ ",
}

local SECTION_OPEN = "▼"
local SECTION_CLOSED = "▶"
local FILE_OPEN = "▼"
local FILE_CLOSED = "▶"

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

local function truncate_display(text, width)
  if width <= 0 then
    return ""
  end
  if display_width(text) <= width then
    return text
  end
  if width == 1 then
    return "…"
  end
  return vim.fn.strcharpart(text, 0, width - 1) .. "…"
end

local function pad_display(text, width)
  return text .. string.rep(" ", math.max(0, width - display_width(text)))
end

local function setup_highlights()
  local defs = {
    GitHubLensTitle = { link = "Title", default = true },
    GitHubLensSection = { link = "Title", default = true },
    GitHubLensFile = { link = "Directory", default = true },
    GitHubLensLineNr = { link = "LineNr", default = true },
    GitHubLensAuthor = { link = "Special", default = true },
    GitHubLensPass = { link = "DiagnosticOk", default = true },
    GitHubLensFail = { link = "DiagnosticError", default = true },
    GitHubLensPending = { link = "DiagnosticWarn", default = true },
    GitHubLensSkipped = { link = "Comment", default = true },
    GitHubLensActionRequired = { link = "DiagnosticWarn", default = true },
    GitHubLensMuted = { link = "Comment", default = true },
    GitHubLensUrl = { link = "Underlined", default = true },
  }
  for name, attrs in pairs(defs) do
    vim.api.nvim_set_hl(0, name, attrs)
  end

  local footer_key_hl = vim.api.nvim_get_hl(0, { name = "GitHubLensSection", link = false })
  footer_key_hl.bold = true
  vim.api.nvim_set_hl(0, "GitHubLensFooterKey", footer_key_hl)
end

---Close the checks and status window if open.
function M.close()
  if M._help_win and vim.api.nvim_win_is_valid(M._help_win) then
    vim.api.nvim_win_close(M._help_win, true)
  end
  M._help_win = nil

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

---Clear cached checks and reset folds.
function M.clear()
  M._folded_sections = {}
  M._folded_files = {}
  M._show_success_override = nil
  M._cached_checks = {}
  M._cached_ctx = nil
  M._cached_comments = {}
  M._action_rows = {}
  M.close()
end

---Check if the status window is currently open.
---@return boolean
function M.is_open()
  return M._win ~= nil and vim.api.nvim_win_is_valid(M._win)
end

---Filter checks according to configuration (default: hide SUCCESS, show all else).
---@param all_checks GitHubLens.Check[]
---@param cfg? GitHubLens.Config|table
---@param show_success_override? boolean
---@return GitHubLens.Check[]
function M.filter_checks(all_checks, cfg, show_success_override)
  local checks_cfg = (cfg and cfg.checks) or {}
  local show_success = show_success_override
  if show_success == nil then
    show_success = checks_cfg.show_success == true
  end
  local custom_filter = checks_cfg.filter

  local filtered = {}
  for _, check in ipairs(all_checks) do
    local keep = true

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
---@param symbols GitHubLens.ConfigSymbols
---@return string sym, string hl_group, string label
local function get_check_status_info(check, symbols)
  if check.conclusion == "SUCCESS" then
    return symbols.pass or "✔", "GitHubLensPass", "passed"
  elseif check.conclusion == "CANCELLED" then
    return symbols.cancelled or "⊘", "GitHubLensSkipped", "cancelled"
  elseif check.conclusion == "SKIPPED" or check.conclusion == "NEUTRAL" then
    return symbols.skipped or "⊘", "GitHubLensSkipped", "skipped"
  elseif check.conclusion == "FAILURE" or check.conclusion == "START_UP_FAILURE" or check.conclusion == "TIMED_OUT" then
    local lbl = check.conclusion == "TIMED_OUT" and "timed out" or "failed"
    return symbols.fail or "✖", "GitHubLensFail", lbl
  elseif check.conclusion == "ACTION_REQUIRED" then
    return symbols.action_required or "◆", "GitHubLensActionRequired", "action required"
  else
    local lbl = (check.status and check.status ~= "") and string.lower(check.status:gsub("_", " ")) or "pending"
    return symbols.pending or "●", "GitHubLensPending", lbl
  end
end

---Toggle the floating help window.
function M.toggle_help()
  if M._help_win and vim.api.nvim_win_is_valid(M._help_win) then
    vim.api.nvim_win_close(M._help_win, true)
    M._help_win = nil
    return
  end

  local help_text = {
    " GitHub Lens Controls",
    "",
    " <CR>      Jump to comment / Open URL / Toggle fold",
    " <Tab>     Toggle fold for section or file",
    " y         Yank URL to system clipboard",
    " s         Toggle showing passed CI checks",
    " r         Refresh pull request data",
    " ] / [     Jump to next / previous item",
    " qf        Send unresolved comments to quickfix",
    " q, <Esc>  Close status window",
    " ?         Close this help window",
  }

  local hbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[hbuf].bufhidden = "wipe"
  vim.bo[hbuf].buftype = "nofile"
  vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, help_text)
  vim.bo[hbuf].modifiable = false

  local width = 50
  local height = #help_text
  local row = math.max(1, math.floor((vim.o.lines - height) / 2))
  local col = math.max(1, math.floor((vim.o.columns - width) / 2))

  local hwin = vim.api.nvim_open_win(hbuf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "single",
  })

  M._help_win = hwin

  local close_help = function()
    if M._help_win and vim.api.nvim_win_is_valid(M._help_win) then
      vim.api.nvim_win_close(M._help_win, true)
    end
    M._help_win = nil
  end

  local kopts = { buffer = hbuf, silent = true, nowait = true }
  vim.keymap.set("n", "q", close_help, kopts)
  vim.keymap.set("n", "<Esc>", close_help, kopts)
  vim.keymap.set("n", "?", close_help, kopts)
  vim.keymap.set("n", "<CR>", close_help, kopts)
end

---Render or re-render the status buffer with current state.
function M.render()
  local buf = M._buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  setup_highlights()

  local checks = M._cached_checks or {}
  local ctx = M._cached_ctx
  local comments = M._cached_comments or {}
  local config = M._cached_config or {}
  local symbols = vim.tbl_extend("force", default_symbols, (config.symbols or {}))

  local show_success = M._show_success_override
  if show_success == nil then
    show_success = config.checks and config.checks.show_success == true
  end

  local displayed_checks = M.filter_checks(checks, config, show_success)

  local lines = {}
  ---@type table<integer, { type: string, url?: string, path?: string, line?: integer, section?: string, id?: string }>
  local line_actions = {}
  ---@type table<integer, { col_start: integer, col_end: integer, hl: string }[]>
  local hl_rows = {}
  M._action_rows = {}

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
      string.format("Pull-Request #%d: %s (%s -> %s)", ctx.number, ctx.title, ctx.head_ref_name, ctx.base_ref_name)
    local header_action = (ctx.url and ctx.url ~= "") and { type = "url", url = ctx.url } or nil
    add_line(pr_header, { { col_start = 0, col_end = #"Pull-Request", hl = "GitHubLensSection" } }, header_action)
    if header_action then
      table.insert(M._action_rows, #lines)
    end
  else
    add_line("GitHub Lens: No active PR context", { { col_start = 0, col_end = -1, hl = "GitHubLensTitle" } })
  end

  add_line("")

  -- 2. CI Checks Section
  local n_fail = 0
  local n_pending = 0
  local n_pass = 0
  for _, c in ipairs(checks) do
    if c.conclusion == "FAILURE" or c.conclusion == "START_UP_FAILURE" or c.conclusion == "TIMED_OUT" then
      n_fail = n_fail + 1
    elseif c.status == "IN_PROGRESS" or c.status == "QUEUED" or c.status == "WAITING" or c.status == "PENDING" then
      n_pending = n_pending + 1
    elseif c.conclusion == "SUCCESS" then
      n_pass = n_pass + 1
    end
  end

  local checks_summary
  if #checks == 0 then
    checks_summary = "Checks (0)"
  elseif #checks == n_pass then
    checks_summary = string.format("Checks (%d) · all passed", #checks)
  else
    local parts = {}
    if n_fail > 0 then
      table.insert(parts, string.format("%d failed", n_fail))
    end
    if n_pending > 0 then
      table.insert(parts, string.format("%d in progress", n_pending))
    end
    if n_pass > 0 and show_success then
      table.insert(parts, string.format("%d passed", n_pass))
    end
    checks_summary = string.format("Checks (%d) · %s", #displayed_checks, table.concat(parts, ", "))
  end

  local is_checks_folded = M._folded_sections["checks"] == true
  local ch_icon = is_checks_folded and SECTION_CLOSED or SECTION_OPEN
  local checks_header_line = string.format("%s %s", ch_icon, checks_summary)
  add_line(checks_header_line, {
    { col_start = 0, col_end = #ch_icon, hl = "GitHubLensMuted" },
    { col_start = #ch_icon + 1, col_end = #ch_icon + 1 + #"Checks", hl = "GitHubLensSection" },
  }, { type = "section_fold", section = "checks" })
  table.insert(M._action_rows, #lines)

  if not is_checks_folded then
    if #displayed_checks == 0 then
      if #checks > 0 then
        local pass_sym = symbols.pass or "✔"
        local pass_line = string.format("  %s All %d checks passed (press 's' to show)", pass_sym, #checks)
        add_line(pass_line, {
          { col_start = 2, col_end = 2 + #pass_sym, hl = "GitHubLensPass" },
          { col_start = 2 + #pass_sym + 1, col_end = #pass_line, hl = "GitHubLensMuted" },
        }, { type = "toggle_success" })
        table.insert(M._action_rows, #lines)
      else
        local pass_sym = symbols.pass or "✔"
        local no_line = string.format("  %s No checks reported for this pull request", pass_sym)
        add_line(no_line, {
          { col_start = 2, col_end = 2 + #pass_sym, hl = "GitHubLensPass" },
          { col_start = 2 + #pass_sym + 1, col_end = #no_line, hl = "GitHubLensMuted" },
        })
      end
    else
      local max_name = 14
      local max_wf = 10
      local max_label = 0
      local max_sym = 1
      for _, c in ipairs(displayed_checks) do
        local name_width = display_width(c.name)
        if name_width > max_name then
          max_name = math.min(28, name_width)
        end
        local wf = (c.workflow ~= "" and c.workflow ~= c.name) and c.workflow or ""
        local wf_width = display_width(wf)
        if wf_width > max_wf then
          max_wf = math.min(20, wf_width)
        end
        local sym, _, label = get_check_status_info(c, symbols)
        max_label = math.max(max_label, display_width(label))
        max_sym = math.max(max_sym, display_width(sym))
      end

      -- Keep the status label visible and make the descriptive columns fit the
      -- window. Workflow names give up space before check names do.
      local window_width = 80
      if M._win and vim.api.nvim_win_is_valid(M._win) then
        window_width = vim.api.nvim_win_get_width(M._win)
      end
      local fixed_width = 2 + max_sym + 1 + 2 + max_label
      local field_width = math.max(1, window_width - fixed_width)
      local desired_fields = max_name + 2 + max_wf
      if desired_fields > field_width then
        local reduce = desired_fields - field_width
        local workflow_reduction = math.min(reduce, max_wf)
        max_wf = max_wf - workflow_reduction
        max_name = math.max(1, max_name - (reduce - workflow_reduction))
      end

      if max_name + 2 + max_wf > field_width then
        max_name = math.max(1, field_width - 2 - max_wf)
      end

      local function format_check(name_text, workflow_text, label, sym)
        if max_wf > 0 then
          return string.format("  %s %s  %s  %s", sym, name_text, workflow_text, label)
        end
        return string.format("  %s %s  %s", sym, name_text, label)
      end

      for _, check in ipairs(displayed_checks) do
        local sym, sym_hl, label = get_check_status_info(check, symbols)
        local wf = (check.workflow ~= "" and check.workflow ~= check.name) and check.workflow or ""
        local display_name = truncate_display(check.name, max_name)
        local display_wf = truncate_display(wf, max_wf)
        local name_text = pad_display(display_name, max_name)
        local workflow_text = pad_display(display_wf, max_wf)
        local check_line = format_check(name_text, workflow_text, label, sym)

        local hls = {
          { col_start = 2, col_end = 2 + #sym, hl = sym_hl },
          { col_start = 2 + #sym + 1, col_end = 2 + #sym + 1 + #display_name, hl = "Normal" },
        }
        if display_wf ~= "" and max_wf > 0 then
          local wf_start = 2 + #sym + 1 + #name_text + 2
          table.insert(hls, { col_start = wf_start, col_end = wf_start + #display_wf, hl = "GitHubLensMuted" })
        end
        local label_start = 2 + #sym + 1 + #name_text + 2
        if max_wf > 0 then
          label_start = label_start + #workflow_text + 2
        end
        local lbl_start = label_start
        table.insert(hls, { col_start = lbl_start, col_end = lbl_start + #label, hl = sym_hl })

        local action = (check.details_url and check.details_url ~= "")
            and { type = "url", url = check.details_url, name = check.name }
          or nil
        add_line(check_line, hls, action)
        table.insert(M._action_rows, #lines)
      end
    end
  end

  add_line("")

  -- 3. Unresolved Review Comments Section
  local n_comments = #comments
  local by_file = {}
  local file_order = {}
  for _, c in ipairs(comments) do
    if not by_file[c.path] then
      by_file[c.path] = {}
      table.insert(file_order, c.path)
    end
    table.insert(by_file[c.path], c)
  end

  local comments_summary
  if n_comments == 0 then
    comments_summary = "Review Comments (0)"
  else
    local file_suffix = #file_order == 1 and "1 file" or (#file_order .. " files")
    comments_summary = string.format("Review Comments (%d unresolved in %s)", n_comments, file_suffix)
  end

  local is_comments_folded = M._folded_sections["comments"] == true
  local cm_icon = is_comments_folded and SECTION_CLOSED or SECTION_OPEN
  local cm_header_line = string.format("%s %s", cm_icon, comments_summary)
  add_line(cm_header_line, {
    { col_start = 0, col_end = #cm_icon, hl = "GitHubLensMuted" },
    { col_start = #cm_icon + 1, col_end = #cm_icon + 1 + #"Review Comments", hl = "GitHubLensSection" },
  }, { type = "section_fold", section = "comments" })
  table.insert(M._action_rows, #lines)

  if not is_comments_folded then
    if n_comments == 0 then
      local pass_sym = symbols.pass or "✔"
      local no_cm_line = string.format("  %s No unresolved review comments", pass_sym)
      add_line(no_cm_line, {
        { col_start = 2, col_end = 2 + #pass_sym, hl = "GitHubLensPass" },
        { col_start = 2 + #pass_sym + 1, col_end = #no_cm_line, hl = "GitHubLensMuted" },
      })
    else
      for _, path in ipairs(file_order) do
        local file_comments = by_file[path]
        local is_file_folded = M._folded_files[path] == true
        local f_icon = is_file_folded and FILE_CLOSED or FILE_OPEN
        local file_line = string.format("  %s %s (%d)", f_icon, path, #file_comments)
        local f_action = { type = "file_fold", path = path }
        local f_hls = {
          { col_start = 2, col_end = 2 + #f_icon, hl = "GitHubLensMuted" },
          { col_start = 2 + #f_icon + 1, col_end = 2 + #f_icon + 1 + #path, hl = "GitHubLensFile" },
          { col_start = 2 + #f_icon + 1 + #path + 1, col_end = #file_line, hl = "GitHubLensMuted" },
        }
        add_line(file_line, f_hls, f_action)
        table.insert(M._action_rows, #lines)

        if not is_file_folded then
          for _, c in ipairs(file_comments) do
            local jump_action = { type = "jump", path = c.path, line = c.line, url = c.url, id = c.id }
            local clean_body = c.body:gsub("\r\n", "\n")
            local body_lines = vim.split(clean_body, "\n", { plain = true })
            local first_body = body_lines[1] or ""
            local lnum_str = string.format("%4d", c.line)
            local author_str = "@" .. c.author
            local comment_line = string.format("      %s  %s  %s", lnum_str, author_str, first_body)

            local c_hls = {
              { col_start = 6, col_end = 10, hl = "GitHubLensLineNr" },
              { col_start = 12, col_end = 12 + #author_str, hl = "GitHubLensAuthor" },
              { col_start = 12 + #author_str + 2, col_end = #comment_line, hl = "Normal" },
            }
            add_line(comment_line, c_hls, jump_action)
            table.insert(M._action_rows, #lines)

            local indent = "            "
            for b_idx = 2, #body_lines do
              local bl = body_lines[b_idx]
              add_line(indent .. bl, { { col_start = #indent, col_end = #indent + #bl, hl = "Normal" } }, jump_action)
            end
          end
        end
      end
    end
  end

  add_line("")

  -- 4. Minimal Footer Section
  local footer_format = "%s %s"
  local footer_items = {
    { key = "?", description = "Help", hl = "GitHubLensFooterKey" },
    { key = "r", description = "Refresh", hl = "GitHubLensFooterKey" },
    { key = "q", description = "Close", hl = "GitHubLensFooterKey" },
  }
  local footer_parts = { "  " }
  local footer_highlights = {}
  local footer_col = 2
  for index, item in ipairs(footer_items) do
    local item_text = string.format(footer_format, item.key, item.description)
    table.insert(footer_parts, item_text)
    table.insert(footer_highlights, {
      col_start = footer_col,
      col_end = footer_col + #item.key,
      hl = item.hl,
    })
    footer_col = footer_col + #item_text
    if index < #footer_items then
      table.insert(footer_parts, "  ")
      footer_col = footer_col + 2
    end
  end
  local footer_line = table.concat(footer_parts)
  add_line(footer_line, footer_highlights, { type = "help" })

  -- Update buffer
  local cur_win = M._win
  local cur_row = 1
  if cur_win and vim.api.nvim_win_is_valid(cur_win) then
    cur_row = vim.api.nvim_win_get_cursor(cur_win)[1]
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

  -- Restore cursor safely
  if cur_win and vim.api.nvim_win_is_valid(cur_win) then
    local target_row = math.max(1, math.min(cur_row, #lines))
    pcall(vim.api.nvim_win_set_cursor, cur_win, { target_row, 0 })
  end

  -- Attach actions map to module for keymap handlers
  M._line_actions = line_actions
end

---Open or update the status buffer in a split or float window.
---@param checks GitHubLens.Check[]
---@param ctx? GitHubLens.PRContext
---@param comments? GitHubLens.Comment[]
---@param config? GitHubLens.Config|table
---@param repo_root? string
function M.open(checks, ctx, comments, config, repo_root)
  M._cached_checks = checks or {}
  M._cached_ctx = ctx
  M._cached_comments = comments or {}
  M._cached_config = config or {}
  M._cached_repo_root = repo_root

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

  local win_cfg = (config and config.window) or {}
  local position = win_cfg.position or "bottom"

  local win = M._win
  if not win or not vim.api.nvim_win_is_valid(win) then
    M._prev_win = vim.api.nvim_get_current_win()

    if position == "float" then
      local width_ratio = win_cfg.width_ratio or 0.7
      local height_ratio = win_cfg.height_ratio or 0.6
      local width = math.max(40, math.floor(vim.o.columns * width_ratio))
      local height = math.max(10, math.floor(vim.o.lines * height_ratio))
      local row = math.max(1, math.floor((vim.o.lines - height) / 2))
      local col = math.max(1, math.floor((vim.o.columns - width) / 2))

      win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        border = win_cfg.border or "single",
        title = " GitHub Lens ",
        title_pos = "center",
      })
    else
      local height_ratio = win_cfg.height_ratio or 0.3
      local height = math.max(6, math.floor(vim.o.lines * height_ratio))

      vim.cmd("botright split")
      win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)
      vim.api.nvim_win_set_height(win, height)
      vim.wo[win].winfixheight = true
    end

    M._win = win

    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = true
    vim.wo[win].wrap = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].spell = false
  else
    if position ~= "float" then
      local height_ratio = win_cfg.height_ratio or 0.3
      local height = math.max(6, math.floor(vim.o.lines * height_ratio))
      vim.api.nvim_win_set_height(win, height)
    end
    vim.api.nvim_win_set_buf(win, buf)
  end

  M.render()

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

  vim.keymap.set("n", "?", function()
    M.toggle_help()
  end, keymap_opts)

  vim.keymap.set("n", "s", function()
    if M._show_success_override == nil then
      local default_show = M._cached_config and M._cached_config.checks and M._cached_config.checks.show_success == true
      M._show_success_override = not default_show
    else
      M._show_success_override = not M._show_success_override
    end
    M.render()
    local status_str = M._show_success_override and "showing all checks (including passed)" or "hiding passed checks"
    vim.notify("[github-lens] CI checks: " .. status_str, vim.log.levels.INFO)
  end, keymap_opts)

  local function toggle_current_fold()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    local action = M._line_actions and M._line_actions[cur_row]
    if action then
      if action.type == "section_fold" and action.section then
        M._folded_sections[action.section] = not M._folded_sections[action.section]
        M.render()
        return
      elseif (action.type == "file_fold" or action.type == "jump") and action.path then
        M._folded_files[action.path] = not M._folded_files[action.path]
        M.render()
        return
      end
    end
  end

  vim.keymap.set("n", "<Tab>", toggle_current_fold, keymap_opts)

  vim.keymap.set("n", "y", function()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    local action = M._line_actions and M._line_actions[cur_row]
    if action and action.url and action.url ~= "" then
      vim.fn.setreg("+", action.url)
      vim.fn.setreg('"', action.url)
      vim.notify("[github-lens] Copied URL to clipboard: " .. action.url, vim.log.levels.INFO)
    elseif action and action.type == "jump" and action.path then
      local loc = string.format("%s:%d", action.path, action.line or 1)
      vim.fn.setreg("+", loc)
      vim.fn.setreg('"', loc)
      vim.notify("[github-lens] Copied location to clipboard: " .. loc, vim.log.levels.INFO)
    else
      vim.notify("[github-lens] Nothing to yank on this line", vim.log.levels.INFO)
    end
  end, keymap_opts)

  vim.keymap.set("n", "]", function()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    for _, r in ipairs(M._action_rows) do
      if r > cur_row then
        vim.api.nvim_win_set_cursor(win, { r, 0 })
        return
      end
    end
  end, keymap_opts)

  vim.keymap.set("n", "[", function()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    for i = #M._action_rows, 1, -1 do
      local r = M._action_rows[i]
      if r < cur_row then
        vim.api.nvim_win_set_cursor(win, { r, 0 })
        return
      end
    end
  end, keymap_opts)

  vim.keymap.set("n", "qf", function()
    require("github-lens").quickfix()
  end, keymap_opts)

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local cur_row = cursor[1]
    local action = M._line_actions and M._line_actions[cur_row]

    if not action then
      vim.notify("[github-lens] No action on this line", vim.log.levels.INFO)
      return
    end

    if action.type == "section_fold" and action.section then
      M._folded_sections[action.section] = not M._folded_sections[action.section]
      M.render()
    elseif action.type == "file_fold" and action.path then
      M._folded_files[action.path] = not M._folded_files[action.path]
      M.render()
    elseif action.type == "toggle_success" then
      M._show_success_override = true
      M.render()
    elseif action.type == "help" then
      M.toggle_help()
    elseif action.type == "url" and action.url then
      vim.ui.open(action.url)
      vim.notify("[github-lens] Opening URL: " .. action.url, vim.log.levels.INFO)
    elseif action.type == "jump" and action.path and action.line then
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
