---@meta

---@alias CheckStatus "QUEUED" | "IN_PROGRESS" | "COMPLETED" | "WAITING" | "PENDING"
---@alias CheckConclusion "ACTION_REQUIRED" | "CANCELLED" | "FAILURE" | "NEUTRAL" | "SUCCESS" | "SKIPPED" | "STALE" | "START_UP_FAILURE" | "TIMED_OUT" | nil

---@class PRLens.Check
---@field name string
---@field workflow string
---@field status CheckStatus
---@field conclusion CheckConclusion
---@field details_url string

---@class PRLens.Comment
---@field id string
---@field author string
---@field body string
---@field path string
---@field line integer
---@field original_line integer
---@field is_resolved boolean
---@field created_at string
---@field url string

---@class PRLens.PRContext
---@field number integer
---@field head_ref_name string
---@field base_ref_name string
---@field url string
---@field title string

---@class PRLens.ConfigKeymaps
---@field toggle_checks? string
---@field refresh? string
---@field clear? string

---@class PRLens.ConfigWindow
---@field position? "bottom" | "float"
---@field height_ratio? number Height ratio for bottom split (e.g. 0.3 for 30%)

---@class PRLens.ConfigChecks
---@field show_success? boolean Whether to show SUCCESS checks (default: false)
---@field filter? (fun(check: PRLens.Check): boolean)|string[] Custom filter predicate or list of allowed conclusions

---@class PRLens.Config
---@field virtual_lines? boolean Show multi-line comment bodies as virtual lines below target code
---@field comment_hl? string Highlight group for comment boundaries
---@field keymaps? PRLens.ConfigKeymaps
---@field window? PRLens.ConfigWindow
---@field checks? PRLens.ConfigChecks

---@class PRLens.State
---@field context PRLens.PRContext|nil
---@field comments PRLens.Comment[]
---@field checks PRLens.Check[]
---@field repo_root string|nil

return {}
