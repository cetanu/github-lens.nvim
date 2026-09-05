# Contributing

## Conventional Commits

Commit messages must use the Conventional Commits format:

```text
<type>(optional scope): <description>
```

Use `feat` for user-facing functionality, `fix` for bug fixes, and `docs`,
`test`, `ci`, or `chore` for other changes. Add `!` after the type or scope,
or a `BREAKING CHANGE:` footer, when a change is incompatible with existing
configuration or behavior.

Release Please uses these commits to calculate the next semantic version and
generate the changelog. It opens a release PR against `master`; merging that
PR creates the corresponding immutable version tag and GitHub release.
