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
  symbols = {
    pass = "✔",
    fail = "✖",
    pending = "●",
    cancelled = "⊘",
    skipped = "⊘",
    action_required = "▲",
    section_open = "▾",
    section_closed = "▸",
    file_open = "▾",
    file_closed = "▸",
    comment_prefix = "│ ",
  },
  keymaps = {
    toggle_checks = "<leader>pc",
    refresh = "<leader>pr",
    clear = "<leader>px",
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

| Command | Action |
| --- | --- |
| `:GitHubLens` | Refresh data and open the status window |
| `:GitHubLens refresh` | Refresh data |
| `:GitHubLens status` | Toggle the status window |
| `:GitHubLens checks` | Alias for `status` |
| `:GitHubLens quickfix` | Open unresolved comments in quickfix |
| `:GitHubLens clear` | Clear comments and close the status window |
| `:GitHubLensChecks` | Toggle the status window |

## Status Window Controls

The status window provides a clean, minimal interface with collapsible sections:

| Key | Action |
| --- | --- |
| `<CR>` | Jump to comment in editor / open URL / toggle fold |
| `<Tab>` / `za` | Toggle fold for current section or file |
| `o` | Open PR, check, or comment URL in browser |
| `y` | Yank URL (or comment location) to clipboard |
| `s` | Toggle showing passed/successful CI checks |
| `r` | Refresh PR comments and checks |
| `]` / `[` | Jump to next / previous actionable item |
| `qf` | Open unresolved comments in quickfix list |
| `?` | Toggle keymap help window |
| `q` / `<Esc>` | Close status window |

## Development

```sh
just check
```

This runs StyLua, Selene, LuaLS, and the headless test suite.

See [`:help github-lens`](doc/github-lens.txt) for the full API and options.

## License

MIT
