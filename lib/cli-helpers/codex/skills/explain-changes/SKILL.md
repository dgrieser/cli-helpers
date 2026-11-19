---
name: explain-changes
description: Briefly explain what a Git branch, uncommitted changes, or a specific commit changes. Use for concise change summaries, not code reviews or implementation work.
---

Explain the user-visible behavior or practical effect of the requested changes in plain language.

If the user supplies no scope, prompt before inspecting patches: "What would you like explained?" Offer these choices:
- Uncommitted changes (staged, unstaged, and untracked)
- Branch changes against a base branch
- A specific commit

Use an available user-input tool when supported in the current mode; otherwise ask the question in chat. Wait for the answer rather than choosing a scope automatically. After branch selection, ask for the base branch, suggesting the locally inferred default; use the current branch unless another is requested. After commit selection, offer recent commits with short hashes and subjects, or accept any commit reference. Read-only Git metadata may be inspected to populate these choices. Keep each prompt short. Explicit arguments or an already specified scope skip the scope prompt; ask only for missing references.

Determine the scope from the selection or request:
- `uncommitted`: inspect staged and unstaged changes against HEAD, plus untracked files. Read relevant untracked files; do not assume they appear in `git diff`.
- `commit <ref>`: inspect that commit's patch and message with `git show`; for a merge commit, compare it with its first parent.
- `branch [ref] [base]`: compare the branch (current branch by default) with its merge base against the requested base. Without a base, infer it from the local remote default-branch reference or repository conventions. Do not treat the branch's upstream as its base automatically. Include only committed branch changes.

Use read-only Git commands and inspect the actual patch, with surrounding code only where needed. Avoid fetching, editing files, running tests, or performing a code review. If the base cannot be inferred reliably, ask only for the base reference. If there are no changes, say so.

Return only a Markdown bullet list with very short points:
- Keep every bullet on one source line, at most 80 characters including indentation and the bullet marker. Do not add continuation lines.
- Express one idea per bullet. Split longer explanations into additional bullets or one level of sub-bullets; do not impose a bullet-count or total-word limit.
- Explain material behavior changes and their practical effects. Use sub-bullets to connect effects or details to a parent change when helpful.
- Identify the scope briefly in the first bullet, including the chosen branch base. Split scope details into sub-bullets if needed to meet the line limit.
- If there are no changes, return one short bullet saying so.
- Prefer behavior over filenames and implementation details. Do not invent motivation or claim tests passed.
- Omit introductory or concluding prose, headings, diff statistics, review findings, and next steps unless requested.

Check each rendered source line's character count before responding and shorten or split any line over 80 characters. Display wrapping depends on the client's width; control source-line length rather than promising a particular visual layout.

Example invocations: `$explain-changes`, `$explain-changes uncommitted`, `$explain-changes branch feature/login main`, `$explain-changes commit HEAD`.
