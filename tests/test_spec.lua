--- Test suite for github-lens.nvim
local M = {}

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(
      string.format(
        "Assertion failed: %s\nExpected: %s\nActual:   %s",
        msg or "",
        vim.inspect(expected),
        vim.inspect(actual)
      )
    )
  end
end

local function assert_true(val, msg)
  if not val then
    error(string.format("Assertion failed (expected true): %s", msg or ""))
  end
end

local function run_tests()
  local passed = 0
  local failed = 0

  local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
      print("  ✔ " .. name)
      passed = passed + 1
    else
      print("  ✖ " .. name)
      print("    " .. tostring(err))
      failed = failed + 1
    end
  end

  print("Running github-lens.nvim tests...\n")

  -- 1. Modules load cleanly
  test("Modules load without error", function()
    local github_lens = require("github-lens")
    local git = require("github-lens.git")
    local gh = require("github-lens.gh")
    local comments = require("github-lens.comments")
    local checks = require("github-lens.checks")

    assert_true(type(github_lens.setup) == "function", "github-lens.setup is a function")
    assert_true(type(github_lens.refresh) == "function", "github-lens.refresh is a function")
    assert_true(type(git.get_pr_context) == "function", "git.get_pr_context is a function")
    assert_true(type(gh.fetch_unresolved_comments) == "function", "gh.fetch_unresolved_comments is a function")
    assert_true(type(comments.set_comments) == "function", "comments.set_comments is a function")
    assert_true(type(checks.open) == "function", "checks.open is a function")
  end)

  -- 2. Git context resolution
  test("Git context parses PR JSON correctly", function()
    local git = require("github-lens.git")
    local orig_system = vim.system
    local mock_json = vim.json.encode({
      number = 42,
      title = "Feat: Add virtual lines",
      url = "https://github.com/org/repo/pull/42",
      headRefName = "feat/virt-lines",
      baseRefName = "main",
    })

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _opts, on_exit)
      assert_eq(cmd[1], "gh", "cmd binary")
      assert_eq(cmd[2], "pr", "cmd sub1")
      assert_eq(cmd[3], "view", "cmd sub2")
      if on_exit then
        on_exit({ code = 0, stdout = mock_json, stderr = "" })
      end
      return {}
    end

    ---@type GitHubLens.PRContext|nil
    local received_ctx = nil
    git.get_pr_context(function(err, ctx)
      assert_eq(err, nil, "no error")
      received_ctx = ctx
    end)

    vim.wait(100, function()
      return received_ctx ~= nil
    end)
    vim.system = orig_system

    assert(received_ctx ~= nil, "context was received")
    assert_eq(received_ctx.number, 42, "PR number")
    assert_eq(received_ctx.title, "Feat: Add virtual lines", "PR title")
    assert_eq(received_ctx.head_ref_name, "feat/virt-lines", "head ref")
    assert_eq(received_ctx.base_ref_name, "main", "base ref")
    assert_eq(received_ctx.url, "https://github.com/org/repo/pull/42", "PR URL")
  end)

  test("Git context handles error gracefully", function()
    local git = require("github-lens.git")
    local orig_system = vim.system

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(_, _, on_exit)
      if on_exit then
        on_exit({ code = 1, stdout = "", stderr = "no pull requests found for current branch\n" })
      end
      return {}
    end

    ---@type string|nil
    local received_err = nil
    git.get_pr_context(function(err, ctx)
      assert_eq(ctx, nil, "ctx is nil on error")
      received_err = err
    end)

    vim.wait(100, function()
      return received_err ~= nil
    end)
    vim.system = orig_system

    assert(received_err ~= nil, "error message received")
    assert_true(string.find(received_err, "no pull requests found") ~= nil, "error message content")
  end)

  -- 3. GH API comments query & filtering
  test("GH API parses GraphQL comments and filters unresolved threads", function()
    local gh = require("github-lens.gh")
    local orig_system = vim.system

    local mock_gql_response = vim.json.encode({
      data = {
        repository = {
          pullRequest = {
            reviewThreads = {
              nodes = {
                {
                  id = "thread-resolved",
                  isResolved = true,
                  path = "lua/foo.lua",
                  line = 10,
                  comments = {
                    nodes = {
                      { id = "c1", author = { login = "alice" }, body = "Already resolved", createdAt = "2026-09-01" },
                    },
                  },
                },
                {
                  id = "thread-open",
                  isResolved = false,
                  path = "lua/bar.lua",
                  line = 25,
                  originalLine = 20,
                  comments = {
                    nodes = {
                      {
                        id = "c3",
                        author = { login = "carol" },
                        body = "Reply to first comment",
                        createdAt = "2026-09-03",
                        url = "https://github.com/org/repo/pull/42#r3",
                      },
                      {
                        id = "c2",
                        author = { login = "bob" },
                        body = "First comment\nSecond line",
                        createdAt = "2026-09-02",
                        url = "https://github.com/org/repo/pull/42#r2",
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    })

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _opts, on_exit)
      assert_eq(cmd[1], "gh", "cmd binary")
      assert_eq(cmd[2], "api", "cmd sub1")
      assert_eq(cmd[3], "graphql", "cmd sub2")
      if on_exit then
        on_exit({ code = 0, stdout = mock_gql_response, stderr = "" })
      end
      return {}
    end

    ---@type GitHubLens.Comment[]|nil
    local comments = nil
    gh.fetch_unresolved_comments(42, nil, function(err, result)
      assert_eq(err, nil, "no error")
      comments = result
    end)

    vim.wait(100, function()
      return comments ~= nil
    end)
    vim.system = orig_system

    assert(comments ~= nil, "comments received")
    assert_eq(#comments, 2, "only 2 unresolved comments (top + reply)")
    assert_eq(comments[1].id, "c2", "comment 1 id")
    assert_eq(comments[1].thread_id, "thread-open", "thread id is populated")
    assert_eq(comments[1].author, "bob", "comment 1 author")
    assert_eq(comments[1].path, "lua/bar.lua", "comment 1 path")
    assert_eq(comments[1].line, 25, "comment 1 line")
    assert_eq(comments[2].id, "c3", "comment 2 id")
    assert_eq(comments[2].author, "carol", "comment 2 author")
    assert_eq(comments[2].body, "Reply to first comment", "comment 2 body")
  end)

  test("GH API mutations use gh api graphql", function()
    local gh = require("github-lens.gh")
    local orig_system = vim.system
    local commands = {}

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _opts, on_exit)
      table.insert(commands, cmd)
      on_exit({ code = 0, stdout = vim.json.encode({ data = { ok = true } }), stderr = "" })
      return {}
    end

    local reply_done = false
    gh.reply_to_thread("thread-1", "Please update this", "/tmp/repo", function(err)
      assert_eq(err, nil, "reply succeeds")
      reply_done = true
    end)
    vim.wait(100, function()
      return reply_done
    end)

    local resolve_done = false
    gh.resolve_thread("thread-1", "/tmp/repo", function(err)
      assert_eq(err, nil, "resolve succeeds")
      resolve_done = true
    end)
    vim.wait(100, function()
      return resolve_done
    end)
    vim.system = orig_system

    assert_eq(#commands, 2, "two mutations invoked")
    for _, cmd in ipairs(commands) do
      assert_eq(cmd[1], "gh", "mutation binary")
      assert_eq(cmd[2], "api", "mutation subcommand")
      assert_eq(cmd[3], "graphql", "mutation endpoint")
      local found_thread = false
      for _, arg in ipairs(cmd) do
        if arg == "thread_id=thread-1" then
          found_thread = true
        end
      end
      assert_true(found_thread, "thread ID passed as a CLI variable")
    end
  end)

  -- 4. GH API checks query & filtering
  test("GH API parses CI checks and strictly filters fail and pending", function()
    local gh = require("github-lens.gh")
    local orig_system = vim.system

    local mock_checks_json = vim.json.encode({
      { name = "lint", state = "SUCCESS", bucket = "pass", workflow = "CI", link = "https://github.com/check/1" },
      {
        name = "unit-tests",
        state = "FAILURE",
        bucket = "fail",
        workflow = "Tests",
        link = "https://github.com/check/2",
      },
      {
        name = "build",
        state = "IN_PROGRESS",
        bucket = "pending",
        workflow = "Build",
        link = "https://github.com/check/3",
      },
      { name = "deploy", state = "SKIPPED", bucket = "skipping", workflow = "CD", link = "https://github.com/check/4" },
    })

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _opts, on_exit)
      assert_eq(cmd[1], "gh", "cmd binary")
      assert_eq(cmd[2], "pr", "cmd sub1")
      assert_eq(cmd[3], "checks", "cmd sub2")
      if on_exit then
        -- Exit code 1 because a check failed
        on_exit({ code = 1, stdout = mock_checks_json, stderr = "" })
      end
      return {}
    end

    ---@type GitHubLens.Check[]|nil
    local checks = nil
    gh.fetch_checks(42, nil, function(err, result)
      assert_eq(err, nil, "no error")
      checks = result
    end)

    vim.wait(100, function()
      return checks ~= nil
    end)
    vim.system = orig_system

    assert(checks ~= nil, "checks received")
    assert_eq(#checks, 4, "all 4 checks parsed (pass, fail, pending, skipping)")
    assert_eq(checks[1].name, "lint", "lint check name")
    assert_eq(checks[1].conclusion, "SUCCESS", "lint check conclusion")
    assert_eq(checks[2].name, "unit-tests", "fail check name")
    assert_eq(checks[2].conclusion, "FAILURE", "fail check conclusion")
    assert_eq(checks[3].name, "build", "pending check name")
    assert_eq(checks[3].status, "IN_PROGRESS", "pending check status")
    assert_eq(checks[4].name, "deploy", "deploy check name")
    assert_eq(checks[4].conclusion, "SKIPPED", "deploy check conclusion")

    -- Verify filter_checks default (hides SUCCESS, shows all else)
    local checks_mod = require("github-lens.checks")
    local default_filtered = checks_mod.filter_checks(checks, { checks = { show_success = false } })
    assert_eq(#default_filtered, 3, "default filter excludes SUCCESS, includes fail/pending/skipped")

    -- Verify show_success = true includes all 4
    local all_filtered = checks_mod.filter_checks(checks, { checks = { show_success = true } })
    assert_eq(#all_filtered, 4, "show_success = true includes all 4 checks")

    -- Verify custom filter
    local fail_only = checks_mod.filter_checks(checks, { checks = { filter = { "FAILURE" } } })
    assert_eq(#fail_only, 1, "custom filter with { 'FAILURE' } returns exactly 1")
  end)

  -- 5. Extmark Buffer Rendering, Virtual Lines & Subdirectory Handling
  test("Buffer comments render extmarks and handle multi-line virtual lines", function()
    local comments_mod = require("github-lens.comments")
    local ns_id = comments_mod.get_namespace()

    local buf = vim.api.nvim_create_buf(false, false)
    local test_file = "/tmp/github_lens_test_repo/src/core.lua"
    vim.api.nvim_buf_set_name(buf, test_file)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "local M = {}",
      "function M.hello()",
      "  print('hello')",
      "end",
      "return M",
    })

    local fake_comments = {
      {
        id = "c100",
        author = "reviewer",
        body = "Line 1 of comment\nLine 2 of comment",
        path = "src/core.lua",
        line = 3,
        original_line = 3,
        is_resolved = false,
        created_at = "2026-09-01",
        url = "https://github.com/org/repo/pull/42#r100",
      },
    }

    local repo_root = "/tmp/github_lens_test_repo"
    comments_mod.set_comments(fake_comments, repo_root, {
      virtual_lines = true,
      comment_hl = "DiagnosticSignInfo",
    })

    -- Check extmarks in buffer
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
    assert_eq(#marks, 1, "exactly 1 extmark placed")
    assert_eq(marks[1][2], 2, "placed on line index 2 (0-indexed line 3)")

    local details = marks[1][4]
    assert(details and details.virt_lines ~= nil, "virt_lines present")
    assert_eq(#details.virt_lines, 2, "2 virtual lines for multi-line comment")

    comments_mod.set_comments(
      {
        fake_comments[1],
        {
          id = "c101",
          author = "another-reviewer",
          body = "Second comment",
          path = "src/core.lua",
          line = 3,
          original_line = 3,
          is_resolved = false,
          created_at = "2026-09-02",
          url = "",
        },
      },
      repo_root,
      {
        virtual_lines = true,
        comment_hl = "DiagnosticSignInfo",
      }
    )
    local grouped_marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
    assert_eq(#grouped_marks, 1, "comments on one line share one extmark")
    assert_eq(#grouped_marks[1][4].virt_lines, 3, "grouped virtual lines preserve both comments")
    assert_true(
      string.find(grouped_marks[1][4].virt_lines[3][2][1], "Second comment", 1, true) ~= nil,
      "second comment follows first comment"
    )

    -- Test persistence across reload and clear
    comments_mod.render_buffer(buf)
    local marks_after_reload = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
    assert_eq(#marks_after_reload, 1, "extmarks do not duplicate on reload")

    -- Test clear
    comments_mod.clear()
    local marks_after_clear = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
    assert_eq(#marks_after_clear, 0, "all extmarks cleared without ghosting")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- 6. Checks & Comments Status split UI window and built-in keymaps
  test("Status UI renders bottom split buffer with checks and comments", function()
    local checks_mod = require("github-lens.checks")

    local sample_checks = {
      {
        name = "test-suite",
        workflow = "Unit Tests",
        status = "COMPLETED",
        conclusion = "FAILURE",
        details_url = "https://github.com/org/repo/actions/runs/12345",
      },
      {
        name = "publish-artifacts",
        workflow = "CI",
        status = "IN_PROGRESS",
        conclusion = nil,
        details_url = "https://github.com/org/repo/actions/runs/67890",
      },
    }

    local sample_comments = {
      {
        id = "c_ui",
        author = "alice",
        body = "Optimize this function",
        path = "lua/github-lens/init.lua",
        line = 10,
        original_line = 10,
        is_resolved = false,
        created_at = "2026-09-01",
        url = "https://github.com/org/repo/pull/124#discussion_r1",
      },
    }

    local ctx = {
      number = 124,
      title = "My PR",
      url = "https://github.com/org/repo/pull/124",
      head_ref_name = "feat",
      base_ref_name = "main",
    }

    checks_mod.open(sample_checks, ctx, sample_comments)

    assert_true(checks_mod._win ~= nil and vim.api.nvim_win_is_valid(checks_mod._win), "win is valid")
    assert_true(checks_mod._buf ~= nil and vim.api.nvim_buf_is_valid(checks_mod._buf), "buf is valid")

    local lines = vim.api.nvim_buf_get_lines(checks_mod._buf, 0, -1, false)
    assert_true(string.find(lines[1], "#124: My PR (feat -> main)", 1, true) ~= nil, "header line")
    assert_true(string.find(lines[3], "Checks (2)", 1, true) ~= nil, "checks section header")
    assert_true(string.find(lines[4], "test-suite", 1, true) ~= nil, "first check name")
    assert_true(string.find(lines[4], "failed", 1, true) ~= nil, "first check status")

    -- Test opening URL via CR on check line (line 4)
    local opened_url = nil
    local orig_open = vim.ui.open
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.open = function(url)
      opened_url = url
      return true
    end

    vim.api.nvim_win_set_cursor(checks_mod._win, { 4, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert_eq(opened_url, "https://github.com/org/repo/actions/runs/12345", "opened check URL on CR")

    -- Test yanking URL via 'y'
    vim.api.nvim_feedkeys("y", "x", false)
    assert_eq(vim.fn.getreg("+"), "https://github.com/org/repo/actions/runs/12345", "yanked URL to clipboard")

    -- Test opening PR URL on header (line 1)
    vim.api.nvim_win_set_cursor(checks_mod._win, { 1, 0 })
    opened_url = nil
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert_eq(opened_url, "https://github.com/org/repo/pull/124", "opened PR URL on CR on header")

    -- Test section folding via Tab on checks header (line 3)
    vim.api.nvim_win_set_cursor(checks_mod._win, { 3, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
    assert_true(checks_mod._folded_sections["checks"] == true, "checks section folded")
    local folded_lines = vim.api.nvim_buf_get_lines(checks_mod._buf, 0, -1, false)
    assert_true(string.find(folded_lines[3], "Checks (2)", 1, true) ~= nil, "checks folded line")

    -- Unfold checks section via Tab
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
    assert_true(checks_mod._folded_sections["checks"] == false, "checks section unfolded")

    -- Test toggle show_success with 's'
    vim.api.nvim_feedkeys("s", "x", false)
    assert_true(checks_mod._show_success_override == true, "show_success toggled on")
    vim.api.nvim_feedkeys("s", "x", false)
    assert_true(checks_mod._show_success_override == false, "show_success toggled off")

    -- Test toggle help window with '?'
    vim.api.nvim_feedkeys("?", "x", false)
    assert_true(checks_mod._help_win ~= nil and vim.api.nvim_win_is_valid(checks_mod._help_win), "help window opened")
    checks_mod.toggle_help()
    assert_true(checks_mod._help_win == nil, "help window closed")

    -- Test comment file folding via Tab
    local file_row = nil
    for r, l in ipairs(vim.api.nvim_buf_get_lines(checks_mod._buf, 0, -1, false)) do
      if string.find(l, "lua/github-lens/init.lua", 1, true) then
        file_row = r
        break
      end
    end
    assert_true(file_row ~= nil, "found file row in comments")
    vim.api.nvim_win_set_cursor(checks_mod._win, { file_row, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
    assert_true(checks_mod._folded_files["lua/github-lens/init.lua"] == true, "file folded")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
    assert_true(checks_mod._folded_files["lua/github-lens/init.lua"] == false, "file unfolded")

    -- Test floating window mode
    checks_mod.close()
    checks_mod.open(sample_checks, ctx, sample_comments, { window = { position = "float", width_ratio = 0.8 } })
    assert_true(checks_mod._win ~= nil and vim.api.nvim_win_is_valid(checks_mod._win), "float win opened")
    local win_config = vim.api.nvim_win_get_config(checks_mod._win)
    assert_eq(win_config.relative, "editor", "window is floating")

    -- Long check metadata should not force the status columns beyond a narrow window.
    checks_mod.close()
    checks_mod.open({
      {
        name = "build-multi-platform-container-image-and-publish",
        workflow = "Container release workflow",
        status = "COMPLETED",
        conclusion = "FAILURE",
      },
    }, ctx, {}, { window = { position = "float", width_ratio = 0.8 } })
    vim.api.nvim_win_set_width(checks_mod._win, 40)
    checks_mod.render()
    local narrow_check_line = vim.api.nvim_buf_get_lines(checks_mod._buf, 3, 4, false)[1]
    assert_true(vim.fn.strdisplaywidth(narrow_check_line) <= 40, "long check fits narrow window")
    assert_true(string.find(narrow_check_line, "…", 1, true) ~= nil, "long check name is truncated")
    assert_true(string.find(narrow_check_line, "failed", 1, true) ~= nil, "status remains visible")

    vim.ui.open = orig_open

    -- Test close
    checks_mod.close()
    assert_true(checks_mod._win == nil, "win closed")
  end)

  -- 7. End-to-end Setup & Init
  test("setup() applies options without configurable keymaps", function()
    local github_lens = require("github-lens")
    github_lens.setup({
      virtual_lines = false,
      comment_hl = "Comment",
      keymaps = {
        refresh = "<leader>tR",
      },
      symbols = {
        action_required = "!",
        section_open = "custom",
        section_closed = "custom",
        file_open = "custom",
        file_closed = "custom",
      },
    })

    assert_eq(github_lens.config.virtual_lines, false, "virtual_lines option")
    assert_eq(github_lens.config.comment_hl, "Comment", "comment_hl option")
    assert_true(github_lens.config.keymaps == nil, "keymaps are not configurable")
    assert_eq(github_lens.config.symbols.action_required, "!", "action_required symbol remains configurable")
    assert_true(github_lens.config.symbols.section_open == nil, "section_open is not configurable")
    assert_true(github_lens.config.symbols.section_closed == nil, "section_closed is not configurable")
    assert_true(github_lens.config.symbols.file_open == nil, "file_open is not configurable")
    assert_true(github_lens.config.symbols.file_closed == nil, "file_closed is not configurable")
  end)

  -- 8. Subdirectory path resolution test
  test("Subdirectory path matching resolves diff paths correctly", function()
    local comments_mod = require("github-lens.comments")
    local ns_id = comments_mod.get_namespace()

    local root = "/tmp/nested_repo"
    local sub_buf = vim.api.nvim_create_buf(false, false)
    -- Buffer opened with nested path
    vim.api.nvim_buf_set_name(sub_buf, "/tmp/nested_repo/subdir/deep/module.lua")
    vim.api.nvim_buf_set_lines(sub_buf, 0, -1, false, {
      "local deep = {}",
      "deep.val = 123",
      "return deep",
    })

    local fake_comments = {
      {
        id = "c_sub",
        author = "alice",
        body = "Nested module comment",
        path = "subdir/deep/module.lua",
        line = 2,
        original_line = 2,
        is_resolved = false,
        created_at = "2026-09-01",
        url = "https://github.com/...",
      },
    }

    comments_mod.set_comments(fake_comments, root, {
      virtual_lines = true,
      comment_hl = "DiagnosticSignInfo",
    })

    local marks = vim.api.nvim_buf_get_extmarks(sub_buf, ns_id, 0, -1, {})
    assert_eq(#marks, 1, "extmark resolved correctly from subdirectory path")

    comments_mod.clear()
    vim.api.nvim_buf_delete(sub_buf, { force = true })
  end)

  -- 9. Quickfix population test
  test("quickfix() populates qflist with unresolved comments", function()
    local github_lens = require("github-lens")
    github_lens.state.comments = {
      {
        id = "qf1",
        author = "charlie",
        body = "Needs test coverage",
        path = "lua/github-lens/init.lua",
        line = 15,
        original_line = 15,
        is_resolved = false,
        created_at = "2026-09-01",
        url = "",
      },
    }
    github_lens.state.repo_root = "/tmp/fake_root"

    github_lens.quickfix()

    local qf = vim.fn.getqflist()
    assert_true(#qf >= 1, "quickfix list has items")
    assert_eq(qf[1].lnum, 15, "quickfix line number")
    assert_true(string.find(qf[1].text, "@charlie: Needs test coverage", 1, true) ~= nil, "quickfix text")
  end)

  -- 10. Plugin user command registration
  test("User command :GitHubLens exists and executes", function()
    -- Load plugin/github-lens.lua
    dofile("plugin/github-lens.lua")

    local commands = vim.api.nvim_get_commands({})
    assert_true(commands["GitHubLens"] ~= nil, ":GitHubLens command registered")
    assert_true(commands["GitHubLensToggle"] == nil, ":GitHubLensToggle command not registered")
  end)

  -- 11. Process Non-Blocking Async Verification
  test("refresh() executes asynchronously via vim.system without blocking", function()
    local github_lens = require("github-lens")
    local orig_system = vim.system
    local calls = {}

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _opts, on_exit)
      table.insert(calls, cmd[1] .. " " .. cmd[2])
      -- Simulate async delayed completion using vim.defer_fn
      if on_exit then
        vim.defer_fn(function()
          if cmd[1] == "git" then
            on_exit({ code = 0, stdout = "/tmp/repo\n", stderr = "" })
          elseif cmd[1] == "gh" and cmd[2] == "pr" and cmd[3] == "view" then
            on_exit({
              code = 0,
              stdout = vim.json.encode({
                number = 99,
                title = "Async PR",
                url = "https://github.com/...",
                headRefName = "branch",
                baseRefName = "main",
              }),
              stderr = "",
            })
          elseif cmd[1] == "gh" and cmd[2] == "api" then
            on_exit({
              code = 0,
              stdout = vim.json.encode({
                data = { repository = { pullRequest = { reviewThreads = { nodes = {} } } } },
              }),
              stderr = "",
            })
          elseif cmd[1] == "gh" and cmd[2] == "pr" and cmd[3] == "checks" then
            on_exit({ code = 0, stdout = "[]", stderr = "" })
          end
        end, 10)
      end
      return {}
    end

    -- Call refresh()
    github_lens.state.last_status = {
      context = {
        number = 98,
        title = "Cached PR",
        url = "https://github.com/...",
        head_ref_name = "cached",
        base_ref_name = "main",
      },
      comments = {},
      checks = {},
      repo_root = "/tmp/repo",
    }
    github_lens.refresh()

    -- Execution returns IMMEDIATELY (non-blocking)
    assert_true(#calls >= 1, "refresh launched async command")
    local cached_lines = vim.api.nvim_buf_get_lines(require("github-lens.checks")._buf, 0, 1, false)
    assert_true(
      string.find(cached_lines[1] or "", "#98: Cached PR", 1, true) ~= nil,
      "cached status renders immediately"
    )

    -- Wait for all deferred async steps to finish
    vim.wait(300, function()
      return github_lens.state.last_status ~= nil and github_lens.state.last_status.context.number == 99
    end)

    vim.system = orig_system

    assert_true(github_lens.state.context ~= nil, "context set after async completion")
    assert_eq(github_lens.state.context.number, 99, "async context number")
    local refreshed_lines = vim.api.nvim_buf_get_lines(require("github-lens.checks")._buf, 0, 1, false)
    assert_true(
      string.find(refreshed_lines[1] or "", "#99: Async PR", 1, true) ~= nil,
      "fresh status replaces cached status"
    )
    assert_eq(github_lens.state.last_status.context.number, 99, "last status snapshot updated")
  end)

  print(string.format("\nTest Summary: %d passed, %d failed", passed, failed))
  if failed > 0 then
    vim.cmd("cquit 1")
  else
    vim.cmd("qa!")
  end
end

run_tests()

return M
