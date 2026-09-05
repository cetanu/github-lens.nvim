# github-lens.nvim

Neovim plugin for GitHub pull request comments and checks.

It shows unresolved review comments in buffers and quickfix, and shows failed
or pending checks in a status window.

## Requirements

- Neovim 0.10 or later
- `git`
- Authenticated GitHub CLI (`gh auth status`)

The plugin has no Lua dependencies.

## Installation

### lazy.nvim

```lua
{
  "cetanu/github-lens.nvim",
  cmd = { "GitHubLens", "GitHubLensChecks" },
  opts = {},
}
```

### packer.nvim

```lua
use({
  "cetanu/github-lens.nvim",
  config = function()
    require("github-lens").setup()
  end,
})
```

## Configuration

```lua
require("github-lens").setup({
  virtual_lines = true,
  comment_hl = "DiagnosticSignInfo",
  keymaps = {
    toggle_checks = "<leader>pc",
    refresh = "<leader>pr",
    clear = "<leader>px",
  },
  window = {
    position = "bottom",
    height_ratio = 0.3,
  },
  checks = {
    show_success = false,
  },
})
```

## Commands

| Command | Action |
| --- | --- |
| `:GitHubLens` | Refresh data and open the status window |
| `:GitHubLens refresh` | Refresh data |
| `:GitHubLens status` | Toggle the status window |
| `:GitHubLens checks` | Alias for `status` |
| `:GitHubLens quickfix` | Open unresolved comments in quickfix |
| `:GitHubLens clear` | Clear comments and close the status window |
| `:GitHubLensChecks` | Toggle the status window |

In the status window:

- `<CR>` jumps to a comment or opens a URL.
- `r` refreshes the data.
- `q` and `<Esc>` close the window.

## Development

```sh
just check
```

This runs StyLua, Selene, LuaLS, and the headless test suite.

See [`:help github-lens`](doc/github-lens.txt) for the full API and options.

## License

MIT
