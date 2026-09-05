# pr-lens.nvim 🔍

A lightweight, zero-external-dependency Neovim plugin for GitHub pull request workflows. Written in stock **LuaJIT (Lua 5.1)** with **LuaCATS** static typing annotations.

`pr-lens.nvim` brings active GitHub PR context directly into your editor:
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
  "pr-lens.nvim",
  cmd = { "PRLens", "PRLensChecks" },
  keys = {
    { "<leader>pr", "<cmd>PRLens refresh<cr>", desc = "PR Lens: Refresh PR data" },
    { "<leader>pc", "<cmd>PRLens checks<cr>", desc = "PR Lens: Toggle CI checks" },
    { "<leader>px", "<cmd>PRLens clear<cr>", desc = "PR Lens: Clear PR data" },
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
  "pr-lens.nvim",
  config = function()
    require("pr-lens").setup()
  end,
})
```

---

## ⚙️ Configuration

Pass your custom configuration to `setup()`:

```lua
require("pr-lens").setup({
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
| `:PRLens` | Refresh PR comments & checks, and open/update status split (default) |
| `:PRLens refresh` | Asynchronously query PR context, review threads, and CI checks |
| `:PRLens status` | Open / toggle the Neogit-style status split buffer at bottom 30% |
| `:PRLens checks` | Alias for `:PRLens status` |
| `:PRLens quickfix` | Populate Neovim's quickfix list with unresolved comments |
| `:PRLens clear` | Wipe all comment extmarks, close status buffer, and reset state |
| `:PRLensChecks` | Direct shortcut to open / toggle the status split buffer |

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
pr-lens.nvim/
├── doc/
│   └── pr-lens.txt       # Vim help documentation (:help pr-lens)
├── lua/
│   └── pr-lens/
│       ├── init.lua      # User setup, public API, keymaps, commands
│       ├── types.lua     # Strict LuaCATS typedefs
│       ├── git.lua       # Git root, current branch, PR detection
│       ├── gh.lua        # GraphQL & REST querying via gh CLI
│       ├── comments.lua  # Extmark & virtual text/lines placement in buffers
│       └── checks.lua    # Floating UI popup renderer for CI checks
├── plugin/
│   └── pr-lens.lua       # Default command registration (:PRLens, :PRLensChecks)
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

