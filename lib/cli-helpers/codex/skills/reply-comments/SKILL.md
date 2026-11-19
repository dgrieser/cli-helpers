---
name: reply-comments
description: Draft and publish very short German replies to open GitHub PR or GitLab MR discussions based on changes already made. Covers general conversation and inline comments. Preview each reply and get explicit approval before posting.
---

# German replies to open threads

Keep each reply to one short German sentence, ideally 5–12 words and at most 20. State what changed or what remains open. Use backticks for identifiers, paths, flags, and literals. Keep progress updates, preview labels, approval prompts, and the final report in English.

## Match feedback to changes

- Identify the requested PR or MR and threads. If the user supplies no target, use the open PR or MR for the current branch. Prefer connected host tools and use `gh` or `glab` as needed. Ask if multiple targets remain plausible.
- Read general conversation comments and inline discussions, including later replies and resolution status where available. A comment without a resolution state can still need a response. Skip unrelated, resolved, or already answered discussions unless the user requests a specific follow-up. Summarize any skipped requested threads in English.
- Check the feedback against the changes. Use the current remote head for published changes and inspect relevant unpushed commits and local edits when the checkout belongs to the PR or MR branch. Compare against the version discussed when available. Distinguish a complete fix from partial work and say when a fix exists only locally. Report checks only when verified.
- Draft one reply per relevant thread. Name the concrete change, for example “`parseConfig` prüft jetzt leere Eingaben.” For a local fix, use wording such as “Die Prüfung auf leere Eingaben ist bisher nur lokal ergänzt.” If evidence is insufficient, explain the gap in the preview and withhold any completion claim.

## Preview and approve

1. Show the PR or MR link and inspected head SHA. Number the proposed replies and show the original comment link or file and line, plus the exact reply body. Identify replies based on local changes and replies that will appear as linked comments in the main conversation.
2. Ask which replies to publish using the available Codex question UI or chat. Let the user approve all, choose numbers, request edits, or cancel. Wait for explicit approval of the displayed replies and targets before any remote write. Show revised replies for approval when the wording or target changes.

## Publish

- Recheck the current head, target thread, relevant changes, and later replies before posting. Skip a duplicate or newly resolved thread and report it. If new evidence changes the reply or target, preview the revision and obtain fresh approval.
- On GitHub, reply to inline review comments using their root comment IDs. For general Conversation comments, post in the PR conversation with a permalink to the original comment in the approved body. On GitLab, reply to inline and general discussions using their discussion IDs. For a standalone note without a reply operation, use a linked MR comment only if that format was previewed and approved. Leave the code, resolution status, and review verdict untouched.
- After a timeout or partial failure, inspect the thread before retrying. Report which replies were posted, with links when available, and identify any approved replies that remain unposted.
