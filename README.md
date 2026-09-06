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
  cmd = { "GitHubLens" },
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
    position = "bottom", -- "bottom" split or "float" centered modal
    height_ratio = 0.3,
    width_ratio = 0.7,   -- used when position is "float"
    border = "rounded",  -- used when position is "float"
  },
  checks = {
    show_success = false,
  },
})
```

## Commands

| Command                | Action                                     |
| ---------------------- | ------------------------------------------ |
| `:GitHubLens`          | Refresh data and open the status window    |
| `:GitHubLens refresh`  | Refresh data                               |
| `:GitHubLens status`   | Toggle the status window                   |
| `:GitHubLens quickfix` | Open unresolved comments in quickfix       |
| `:GitHubLens clear`    | Clear comments and close the status window |

## Controls within the window

The status window provides a interface with collapsible sections:

| Key           | Action                                      |
| ------------- | ------------------------------------------- |
| `?`           | Toggle help window                          |
| `<CR>`        | Jump to comment in editor / open URL        |
| `<Tab>`       | Collapse/expand current section or file     |
| `y`           | Yank URL (or comment location) to clipboard |
| `s`           | Toggle display of successful CI checks      |
| `r`           | Refresh comments and checks                 |
| `]` / `[`     | Jump to next / previous actionable item     |
| `qf`          | Open unresolved comments in quickfix list   |
| `q` / `<Esc>` | Close window                                |

## Development

```sh
just check
```

This runs Stylua, Selene, LuaLS, and the headless test suite.

See [`:help github-lens`](doc/github-lens.txt) for the full API and options.

## License

MIT
