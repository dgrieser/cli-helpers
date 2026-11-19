# Bash CLI Tool Instructions

This document defines the basic conventions for a simple Bash command-line tool.
It is written to match the structure and behavior shown in the example script.

## Purpose

- Keep the script small, readable, and predictable.
- Use a single entry point with clear option parsing.
- Prefer explicit failure over silent fallback behavior.
- Make the `--help` output the primary source of usage guidance.

## Script Structure

Use this order:

1. Shebang and app name
2. Helper functions
3. Default variable initialization
4. Argument parsing loop
5. Validation
6. Main action

Example:

```bash
#!/bin/bash

APP_NAME="$(basename "${0}")"
```

## Required Helper Functions

Define small helpers for consistent messaging:

- `usage()`: print help text to stderr and exit non-zero
- `error()`: print an error message to stderr
- `warning()`: print a warning message to stderr
- `fail()`: print an error message and exit non-zero
- `abort()`: print a user-facing abort message and exit non-zero

Keep these helpers simple and reusable.

Example:

The following example includes one command, for tools without commands, COMMAND can be omitted.

```bash
usage() {
    cat <<EOF 1>&2
usage: ${APP_NAME} COMMAND [OPTIONS]

Describe the tool's purpose here.

Commands:
  do-something          Describe the command here
  do-another-thing      Describe the command here

Options:
  -f, --flag            Describe the option's behavior here
  -o, --output OUTPUT   Describe the option's behavior here
  -h, --help            Show this help message and exit
EOF
    exit 1
}

error() {
    echo "ERROR: ${1}" 1>&2
}

warning() {
    echo "WARNING: ${1}" 1>&2
}

fail() {
    error "${1}"
    exit 1
}

abort() {
    echo "Abort." 1>&2
    exit 1
}
```

## Usage Output

The `usage()` function should:

- Print to stderr
- Show the command name using `${APP_NAME}`
- List supported options
- Briefly describe the tool’s purpose
- Exit with status `1`

The help text should be concise and formatted like a standard CLI.

## Option Parsing Rules

Use a `while [ "${#}" -gt 0 ]` loop with a `case` statement.

Follow these conventions:

- Support both short and long options when practical
- Consume option arguments immediately after the flag
- Validate that flags requiring values actually receive them
- Reject unknown options
- Reject unexpected positional arguments unless the script explicitly supports them

Example pattern:

```bash
flag=0
while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -h|--help)
            usage
            ;;
        -f|--flag)
            flag=1
            ;;
        -o|--output)
            shift
            [ -z "${1}" ] && usage
            # optionally check for expected format
            output="${1}"
        -*)
            error "Unknown option: ${1}"
            usage
            ;;
        *)
            error "Unexpected argument: ${1}"
            usage
            ;;
    esac
    shift
done
```

## Defaults And Validation

- Initialize all option variables before parsing.
- Use simple scalar defaults like `0`, `""`, or `"false"` style values.
- Validate required inputs after parsing and before executing the main action.
- Call `usage()` when required parameters are missing.

## Error Handling

Use one of these patterns:

- `error "message"` for non-fatal reporting
- `fail "message"` for fatal errors
- `abort` for explicit user cancellation

Guidelines:

- Send errors to stderr
- Use short, direct messages
- Avoid ambiguous failures
- Prefer consistent phrasing across the script

## Main Logic

After validation, execute the requested action based on parsed flags.

Recommendations:

- Keep the main path separate from parsing
- Branch clearly on mutually exclusive modes
- Avoid deeply nested conditionals
- Use dedicated functions for substantial operations

## Style Guidelines

- Quote variable expansions unless you intentionally want word splitting.
- Prefer `[` and `]` consistently with POSIX-style shell syntax.
- Use readable names for flags and variables.
- Keep functions short and single-purpose.
- Prefer explicit behavior over clever shell tricks.
- Do not use `set` to change shell options unless the script explicitly requires it and the behavior is documented.

## Recommended Behavior For This CLI Pattern

For a tool like this, the script should:

- Support `--help`
- Support feature flags and options with arguments as needed
- Require any mandatory argument after parsing
- Fail fast on invalid combinations or missing values
- Make the default action clear and deterministic

## Example Contract

The template implies this contract:

- Each flag should have a single, clearly documented purpose
- Options that take values should validate those values before use
- `--help` prints usage and exits

If a flag changes behavior significantly, document that directly in the usage text.

## Minimal Quality Bar

Before considering the script complete:

- Help output is accurate
- Unknown options are rejected
- Missing option values are handled safely
- Required inputs are validated
- Messages are consistent
- The script exits with the right status codes
