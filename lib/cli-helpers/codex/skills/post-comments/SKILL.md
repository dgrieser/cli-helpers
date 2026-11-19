---
name: post-comments
description: Draft extremely short German inline review comments with applicable code suggestions for the current branch's GitHub PR or GitLab MR, preview them, and publish only after explicit approval. Use when asked to post review findings; ordinary code review alone does not request this workflow.
---

# German inline review suggestions

Turn review findings into very short German inline comments, each with a directly applicable fix. Preview only the German comment prose and its code location; do not display suggestion code unless asked. Prepare applicable fixes internally and obtain approval before creating anything remotely, including pending reviews or draft comments.

## Language

Keep all conversation, progress updates, preview labels, explanations, approval questions and choices, and final reports in English. Only the review comment prose is German, including when shown in the preview. Keep code in its original language.

## Identify the review

- Resolve the current repository, branch, hosting service, and corresponding open PR/MR from local Git metadata and the host. Prefer available connected tools; use `gh` or `glab` when needed. Do not assume GitHub, `origin`, or a default base branch. Ask if multiple targets remain plausible; never create a PR/MR.
- Read the current remote diff, head SHA, base/diff references, relevant code, and existing review threads. Review the PR/MR head, not unpushed working-tree changes. Preserve local files.
- Reuse findings already established in this conversation after verifying them against the current diff. If none exist, review the branch diff for concrete actionable defects. Exclude speculative concerns, praise, style-only nits, resolved findings, and duplicate existing comments. If no findings qualify, report that and stop.

## Compose

- One defect per comment. German prose: one short sentence, aim for 5–12 words, maximum 20 words excluding code. State the concrete problem or effect. No greeting, title, severity prefix, background essay, or review summary in the posted body.
- Put code identifiers, paths, flags, and literals in Markdown backticks. Keep code in its original language and preserve project style and indentation.
- Every posted comment MUST include a native, applicable `suggestion` code block containing the exact replacement, not a patch, pseudocode, ellipsis, or instructions. Include the complete replacement for the anchored range, preserving any necessary surrounding lines.
- Use the smallest contiguous range that correctly fixes the defect. Validate that replacing those exact lines produces valid, appropriate code. Run a focused check when needed; do not claim checks that were not run.
- GitHub: anchor the comment to the correct diff side and line, using a multiline range when necessary; the suggestion replaces that anchored range.
- GitLab: use a positioned diff discussion with the current base/start/head SHAs and correct old/new paths and lines. For replacement beyond the anchor, use the host's native `suggestion:-N+M` range offsets, calculated against the actual file. Confirm supported API fields and syntax from current host documentation or tool schemas when uncertain.
- If a complete safe fix needs disjoint edits or unavailable context, do not publish a partial suggestion as a fix. Explain the limitation briefly in the local preview and omit it from the publishable set unless a complete applicable suggestion becomes possible.

Example single-line comment body (outer fence is only for this example):

````markdown
`items[0]` löst bei leerer Liste einen Fehler aus.

```suggestion
return items[0] if items else None
```
````

## Preview and approval

1. Show the target PR/MR link and reviewed head SHA, then number each proposed comment. For each, show its file, exact line/range and side, and only the final German prose with Markdown code identifiers. Do not show suggestion blocks, replacement code, patches, or fix previews unless explicitly requested. Prepare and verify the full native suggestion internally before requesting approval; every published comment still includes it.
2. Ask: “Which comments should I publish? All, selected numbers, or edits?” Use the available Codex question UI with choices for publishing all, selecting/editing, or cancelling. Prefer `request_user_input_async` when available; use `request_user_input` only where the current mode allows it. If no question tool is available, ask in chat.
3. Wait for an explicit answer. An initial request to post findings is not approval of unseen comment prose. Approval of the displayed prose authorizes posting that prose together with its internally prepared applicable code suggestion; the user explicitly does not require a code suggestion preview. Neither a default selection nor silence counts as approval. Do not call any remote write tool while awaiting it.
4. Apply requested edits and show revised comments for approval again. Approval covers the exact prose, ranges, and target shown, plus the internally prepared fix for each approved finding. A changed finding, prose, or range needs fresh approval; suggestion code need not be displayed. Publish only the approved subset; do not ask again for unchanged, already approved comments.

## Publish

- Immediately before posting, recheck target head/diff and existing threads. If the head changed, revalidate and show updated proposals for fresh approval. Skip comments already present and report the skip.
- Post the approved bodies as native inline review comments/discussions at the approved code ranges. Use structured tool arguments or JSON/body files with `gh`/`glab`; preserve Markdown and literal code exactly without shell interpolation.
- Do not apply suggestions, push commits, merge, resolve discussions, or submit an approval/request-changes verdict. If the API requires a review event, use a neutral comment review.
- If an API cannot create the approved inline suggestion, report the limitation; do not substitute a general PR/MR comment or silently change the body/range.
- After a timeout or partial failure, inspect remote state before retrying to avoid duplicates. Stop on unresolved write failure and report posted versus unposted items. Return links to the created comments when available.
