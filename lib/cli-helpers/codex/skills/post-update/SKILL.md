---
name: post-update
description: Draft and publish a short German top-level GitHub PR or GitLab MR comment about completed changes from the current work that the description and existing comments do not already cover. Use when asked to post an update on what was done. Preview the comment for explicit approval before posting.
---

# Post a change update

## Find what is new

- Use the requested PR or MR, or find the open one for the current branch. Prefer connected host tools, with `gh` or `glab` as needed. Ask if the target is ambiguous.
- Identify work completed in the current task or the range the user specifies. Verify it against the PR or MR diff and relevant commits. Check local changes only when the checkout belongs to the target branch. Mark any work that exists only locally as such and mention verification only when confirmed.
- Read the current description and all existing comments, including general conversation, review summaries, inline comments, and replies in resolved threads. Compare by meaning. A request to make a change does not establish that it was made. If a broad description covers part of the work, include only meaningful new details. If nothing new remains, report that and stop.

## Draft and approve

- Draft one concise, top-level comment in German. Use a sentence for one change or short bullets for several. Describe concrete outcomes that matter to someone reading the PR or MR. Keep the surrounding conversation in English.
- Show the PR or MR link and exact comment body. Wait for explicit approval before posting. Preview any revised body or target for fresh approval.

## Publish

- Before posting, recheck the head, description, and comments for changes that affect the update. If the update is now fully covered, stop. If only part remains new, preview the trimmed text and get fresh approval.
- Post the approved body as a general comment on the PR or MR. Leave the description, code, and discussion states untouched. If the write times out, check the conversation before retrying. Return the posted comment link or report the failure.
