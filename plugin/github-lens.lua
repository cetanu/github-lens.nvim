if vim.g.loaded_github_lens == 1 then
  return
end
vim.g.loaded_github_lens = 1

local subcommands = {
  refresh = function()
    require("github-lens").refresh()
  end,
  status = function()
    require("github-lens").show_checks()
  end,
  clear = function()
    require("github-lens").clear()
  end,
  quickfix = function()
    require("github-lens").quickfix()
  end,
}

vim.api.nvim_create_user_command("GitHubLens", function(opts)
  local arg = vim.trim(opts.args or "")
  if arg == "" or arg == "refresh" then
    subcommands.refresh()
  elseif subcommands[arg] then
    subcommands[arg]()
  else
    vim.notify(
      string.format("[github-lens] Unknown subcommand: '%s'. Valid options: refresh, status, clear, quickfix", arg),
      vim.log.levels.ERROR
    )
  end
end, {
  nargs = "?",
  complete = function(arg_lead)
    local matches = {}
    for cmd, _ in pairs(subcommands) do
      if vim.startswith(cmd, arg_lead) then
        table.insert(matches, cmd)
      end
    end
    table.sort(matches)
    return matches
  end,
  desc = "GitHub Lens: Manage pull request review comments and CI checks",
})
