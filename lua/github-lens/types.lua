---@meta

---@alias CheckStatus "QUEUED" | "IN_PROGRESS" | "COMPLETED" | "WAITING" | "PENDING"
---@alias CheckConclusion "ACTION_REQUIRED" | "CANCELLED" | "FAILURE" | "NEUTRAL" | "SUCCESS" | "SKIPPED" | "STALE" | "START_UP_FAILURE" | "TIMED_OUT" | nil

---@class GitHubLens.Check
---@field name string
---@field workflow string
---@field status CheckStatus
---@field conclusion CheckConclusion
---@field details_url string

---@class GitHubLens.Comment
---@field id string
---@field author string
---@field body string
---@field path string
---@field line integer
---@field original_line integer
---@field is_resolved boolean
---@field created_at string
---@field url string

---@class GitHubLens.PRContext
---@field number integer
---@field head_ref_name string
---@field base_ref_name string
---@field url string
---@field title string

---@class GitHubLens.ConfigSymbols
---@field pass? string
---@field fail? string
---@field pending? string
---@field cancelled? string
---@field skipped? string
---@field action_required? string
---@field comment_prefix? string

---@class GitHubLens.ConfigWindow
---@field position? "bottom" | "float"
---@field height_ratio? number Height ratio for bottom split or float (e.g. 0.3 for 30%)
---@field width_ratio? number Width ratio for float (e.g. 0.7 for 70%)
---@field border? string | string[] Border style for floating window (default: "single")

---@class GitHubLens.ConfigChecks
---@field show_success? boolean Whether to show SUCCESS checks (default: false)
---@field filter? (fun(check: GitHubLens.Check): boolean)|string[] Custom filter predicate or list of allowed conclusions

---@class GitHubLens.Config
---@field virtual_lines? boolean Show multi-line comment bodies as virtual lines below target code
---@field comment_hl? string Highlight group for comment boundaries
---@field symbols? GitHubLens.ConfigSymbols Custom symbols/icons for UI
---@field window? GitHubLens.ConfigWindow
---@field checks? GitHubLens.ConfigChecks

---@class GitHubLens.State
---@field context GitHubLens.PRContext|nil
---@field comments GitHubLens.Comment[]
---@field checks GitHubLens.Check[]
---@field repo_root string|nil

return {}
