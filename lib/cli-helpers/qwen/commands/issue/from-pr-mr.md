---
description: Generate a suitable issue title and description for an existing push request/merge request
---

Please generate a suitable issue title and description for an existing pull request/merge request.

# Guidelines

The title and description should be the reverse, e.g. describing what is broken, not how it was fixed by the pull request/merge request.

# Output
Make sure to output the response in **valid** JSON format.

## Output schema - MUST MATCH *exactly*

```json
{
    "title": "<max 80 characters, plain text, no markdown>",
    "description": "<valid, well formatted, markdown with multiple lines>"
}
```

* **Do not** wrap the JSON in markdown fences or extra prose.

# Pull request/merge request

This is the pull request/merge request to be converted to an issue:

{{ args }}
