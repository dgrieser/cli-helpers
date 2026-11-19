---
description: Run golangci-lint and fix all legitimate errors
---

Check if `Makefile` exists and contains `lint` target, then:
run `make lint`.

Otherwise:
run `golangci-lint run --enable modernize`

For every reported error:
- Identify its root cause and make the minimal correct code change.
- Do not disable, weaken, suppress, or reconfigure lint rules.
- Do not edit the Makefile, lint configuration, dependencies, or generated files merely to make lint pass.
- Preserve the repository’s existing style and conventions.

Rerun lint command after making fixes. Repeat until it exits successfully.

When complete:
1. Run `git diff --check`.
2. Show `git diff`.
3. Summarize the lint failures fixed and any remaining blockers.
