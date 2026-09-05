if vim.g.loaded_pr_lens == 1 then
  return
end
vim.g.loaded_pr_lens = 1

local subcommands = {
  refresh = function()
    require("pr-lens").refresh()
  end,
  checks = function()
    require("pr-lens").show_checks()
  end,
  status = function()
    require("pr-lens").show_checks()
  end,
  clear = function()
    require("pr-lens").clear()
  end,
  quickfix = function()
    require("pr-lens").quickfix()
  end,
}

vim.api.nvim_create_user_command("PRLens", function(opts)
  local arg = vim.trim(opts.args or "")
  if arg == "" or arg == "refresh" then
    subcommands.refresh()
  elseif subcommands[arg] then
    subcommands[arg]()
  else
    vim.notify(
      string.format("[pr-lens] Unknown subcommand: '%s'. Valid options: refresh, checks, clear, quickfix", arg),
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
  desc = "PR Lens: Manage pull request review comments and CI checks",
})

vim.api.nvim_create_user_command("PRLensChecks", function()
  require("pr-lens").show_checks()
end, {
  desc = "PR Lens: Open floating window with failing and pending CI checks",
})
