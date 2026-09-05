# github-lens.nvim 🔍

A lightweight, zero-external-dependency Neovim plugin for GitHub pull request workflows. Written in stock **LuaJIT (Lua 5.1)** with **LuaCATS** static typing annotations.

`github-lens.nvim` brings active GitHub PR context directly into your editor:
- **Unresolved Review Comments**: Projected right inside target buffers as inline virtual lines (`extmarks`) on their respective files and lines, or navigable in the quickfix list.
- **Failing & Pending CI Checks**: Displayed in an interactive floating popup window with one-key browser navigation (`<CR>`).

---

## ✨ Features

- ⚡ **Zero Lua Runtime Dependencies**: No `plenary.nvim` or heavy frameworks. Pure Neovim APIs.
- 🚀 **100% Asynchronous**: All CLI queries (`git`, `gh`) run off the main thread via `vim.system()`. Your editing experience never hitches or blocks.
- 🧵 **Thread-Aware Unresolved Comments**: Fetches PR review threads via the GitHub GraphQL API, isolating unresolved comments and replies without background polling.
- 🛡️ **Interactive CI Checks Popup**: Compact floating window displaying failing (`[FAIL]`) and pending/in-progress (`[WAIT]`) GitHub Actions checks, with instant `<CR>` URL navigation via `vim.ui.open()`.
- 📁 **Repository Root & Subdirectory Awareness**: Accurately resolves GitHub file paths even when editing from nested project subdirectories.
- 🔄 **Buffer Lifecycle Handling**: Extmarks persist smoothly across buffer reloads (`:e`) and clean up completely on demand without ghosting.

---

## 📋 Requirements

- **Neovim >= 0.10.0** (required for native `vim.system()` and `vim.iter()`)
- **Git** CLI (`git`)
- **GitHub CLI** (`gh`) authenticated (`gh auth status`)

---

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "github-lens.nvim",
  cmd = { "GitHubLens", "GitHubLensChecks" },
  keys = {
    { "<leader>pr", "<cmd>GitHubLens refresh<cr>", desc = "GitHub Lens: Refresh PR data" },
    { "<leader>pc", "<cmd>GitHubLens checks<cr>", desc = "GitHub Lens: Toggle CI checks" },
    { "<leader>px", "<cmd>GitHubLens clear<cr>", desc = "GitHub Lens: Clear PR data" },
  },
  opts = {
    virtual_lines = true,
    comment_hl = "DiagnosticSignInfo",
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({
  "github-lens.nvim",
  config = function()
    require("github-lens").setup()
  end,
})
```

---

## ⚙️ Configuration

Pass your custom configuration to `setup()`:

```lua
require("github-lens").setup({
  -- Display multi-line comment bodies as virtual lines below target code
  virtual_lines = true,

  -- Highlight group for the comment prefix and border
  comment_hl = "DiagnosticSignInfo",

  -- Default keymaps (set to empty strings or false to disable individual keys)
  keymaps = {
    toggle_checks = "<leader>pc",
    refresh = "<leader>pr",
    clear = "<leader>px",
  },

  -- Neogit-style status split buffer settings
  window = {
    position = "bottom", -- "bottom" or "float"
    height_ratio = 0.3,  -- bottom 30% of the window
  },

  -- CI Checks display settings
  checks = {
    show_success = false, -- Default: false (hides SUCCESS, shows all else: fail, pending, cancelled, skipped)
    -- filter = { "FAILURE", "CANCELLED", "PENDING" }, -- Optional: whitelist or filter predicate function
  },
})
```

---

## ⌨️ Commands

| Command | Description |
|---|---|
| `:GitHubLens` | Refresh PR comments & checks, and open/update status split (default) |
| `:GitHubLens refresh` | Asynchronously query PR context, review threads, and CI checks |
| `:GitHubLens status` | Open / toggle the Neogit-style status split buffer at bottom 30% |
| `:GitHubLens checks` | Alias for `:GitHubLens status` |
| `:GitHubLens quickfix` | Populate Neovim's quickfix list with unresolved comments |
| `:GitHubLens clear` | Wipe all comment extmarks, close status buffer, and reset state |
| `:GitHubLensChecks` | Direct shortcut to open / toggle the status split buffer |

---

## 🖥️ Status Buffer Keymaps

Inside the bottom status split window:
- `<CR>`:
  - **On comments (`📍 file:line` or body)**: Jumps directly to the file and line in the editor window above.
  - **On CI checks or links**: Opens the check URL in your default web browser via `vim.ui.open()`.
  - **On PR URL**: Opens the PR in your default web browser.
- `r`: Refresh PR review comments and CI checks.
- `q` or `<Esc>`: Close the status split window and return focus to the editor.

---

## 🧩 Architecture

```text
github-lens.nvim/
├── doc/
│   └── github-lens.txt       # Vim help documentation (:help github-lens)
├── lua/
│   └── github-lens/
│       ├── init.lua      # User setup, public API, keymaps, commands
│       ├── types.lua     # Strict LuaCATS typedefs
│       ├── git.lua       # Git root, current branch, PR detection
│       ├── gh.lua        # GraphQL & REST querying via gh CLI
│       ├── comments.lua  # Extmark & virtual text/lines placement in buffers
│       └── checks.lua    # Floating UI popup renderer for CI checks
├── plugin/
│   └── github-lens.lua       # Default command registration (:GitHubLens, :GitHubLensChecks)
├── .stylua.toml
└── README.md
```

---

## 🧪 Development & Linting

Verify formatting and typing with:

```bash
# Code formatting
stylua --check .

# Linting
selene .

# Type checking
lua-language-server --check .
```

---

## 📄 License

MIT

