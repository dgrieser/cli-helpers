# cli-helpers

A collection of small, single-purpose command-line tools, mostly Bash, some Python, for:
- Audio
- Clipboard
- Window/Display management
- AI helpers
- Text Processing/Conversion
- and day-to-day shell ergonomics

Built for Linux, running on GNOME with either X11 or Wayland.

## Installation

The repo ships a `Makefile` that installs every executable into `$(PREFIX)/bin` (default `/usr/local/bin`) and shared helpers into `$(PREFIX)/lib/cli-helpers`, and packages/enables the bundled GNOME Shell extension used by the window tools on Wayland. Commands that double as importable Python modules (`toage`) are installed a second time as `<name>.py` into `$(PREFIX)/lib/python3/dist-packages`, which `/etc/profile.d/python.sh` puts on `PYTHONPATH`, so other tools can import them instead of piping through them.

```bash
make list                     # show targets and the full command list
make update                   # update installed software (use UPDATE_ARGS='--dry-run apt')
sudo make install-links       # install as symlinks back to this repo (no copy)
sudo make install             # copy commands + shared helpers + GNOME extension
sudo make uninstall           # remove installed files
make list-install             # show install destinations
```

Override paths with `PREFIX=...`, `BINDIR=...`, `LIBDIR=...`, `PYTHONDIR=...`.  
set `ENABLE_GNOME_EXTENSION=0` to skip the GNOME extension step.

## Contents

- [Audio Media](#audio-media)
- [Webcam](#webcam)
- [Clipboard](#clipboard)
- [AI Helpers](#ai-helpers)
- [Color and Terminal Text Styling](#color-and-terminal-text-styling)
- [Text and Data Processing](#text-and-data-processing)
- [Format, Encoding and Conversion](#format-encoding-and-conversion)
- [Files and Shell Command Helpers](#files-and-shell-command-helpers)
- [Interactive Input Prompts](#interactive-input-prompts)
- [SSH, Network and System](#ssh-network-and-system)
- [Window and Display Management](#window-and-display-management)

---

## Audio Media

### `audio-levels`
Continuously displays live audio statistics from a PulseAudio source using `sox`, stopping when Esc, `q`, or Enter is pressed.

**Usage:** `audio-levels [-h|--help|--list-devices] <pulseaudio-device>`

| Argument / Flag | Description |
|---|---|
| `<pulseaudio-device>` | The PulseAudio source device to monitor. Defaults to `default` if omitted. |
| `-h, --help` | Show the usage message. |
| `--list-devices` | List available PulseAudio source device names and exit. |
| `--bash-completion` | Output completion candidates (flags plus device names) for shell completion. |

**Examples:**
```bash
audio-levels --list-devices
audio-levels
audio-levels alsa_input.pci-0000_00_1f.3.analog-stereo
```

### `audio-normalize`
Detects the maximum volume of an audio file and re-encodes it to an MP3 with that peak shifted to 0 dB (normalized), writing the result to `<file>_normalized.mp3`.

**Usage:** `audio-normalize <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The input audio file to normalize. |

**Examples:**
```bash
audio-normalize recording.mp3
audio-normalize interview.wav
```

### `audio-renamer`
Renames every `.mp3` file in the current directory based on its embedded title tag, sanitizing the title into a safe filename and appending a numeric suffix to avoid collisions (falling back to `ole` when no title is present).

**Usage:** `audio-renamer`

Takes no arguments.

**Examples:**
```bash
cd ~/Music/album && audio-renamer
```

### `audio-restart`
Restarts the user's PipeWire and WirePlumber services to recover from audio problems.

**Usage:** `audio-restart`

Takes no arguments.

**Examples:**
```bash
audio-restart
```

### `audio-segment`
Splits an audio file into fixed-length segments using `ffmpeg` (stream copy, no re-encoding) and prints the names of the generated segment files.

**Usage:** `audio-segment [-h|--help] [-v|--verbose] [-s|--segment-seconds <seconds>] <input file> [<output file basename>]`

| Argument / Flag | Description |
|---|---|
| `<input file>` | The audio file to split into segments. |
| `<output file basename>` | Base name for the output segments; defaults to `<input file without extension>_seg`. Segments are named `<basename>_<index>.<ext>`. |
| `-h, --help` | Show the usage message. |
| `-v, --verbose` | Enable verbose output and `ffmpeg` verbose logging. |
| `-s, --segment-seconds <seconds>` | Length of each segment in seconds (must be a positive integer). Defaults to `600`. |

**Examples:**
```bash
audio-segment lecture.mp3
audio-segment -s 300 podcast.mp3
audio-segment --verbose --segment-seconds 120 recording.wav chunk
```

### `audio-trim`
Trims an audio file between a start time and an optional end time (defaulting to the file's full duration) and re-encodes the result to MP3, writing it to `<audio-file>_trimmed.<ext>`.

**Usage:** `audio-trim <audio-file> <start-time> [<end-time>]`

| Argument / Flag | Description |
|---|---|
| `<audio-file>` | The input audio file to trim. |
| `<start-time>` | Start time in `HH:MM:SS` or `HH:MM:SS.ms` format. |
| `<end-time>` | Optional end time in `HH:MM:SS` or `HH:MM:SS.ms` format; defaults to the file's full duration. |

**Examples:**
```bash
audio-trim song.mp3 00:00:30
audio-trim interview.mp3 00:01:15 00:05:45.5
```

### `audio-volume`
Adjusts an audio file's volume by a given decibel amount, re-encoding it to a temporary MP3 file and printing the new file's path.

**Usage:** `audio-volume <file> <volume>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The input audio file. |
| `<volume>` | The volume adjustment in decibels (e.g. `5` to boost, `-3` to reduce), passed to the `ffmpeg` `volume` filter as `<volume>dB`. |

**Examples:**
```bash
audio-volume quiet.mp3 6
audio-volume loud.mp3 -4
```

### `audio-volume-detect`
Detects and prints the maximum volume (in dB) of an audio file using the `ffmpeg` `volumedetect` filter.

**Usage:** `audio-volume-detect <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The audio file to analyze. |

**Examples:**
```bash
audio-volume-detect recording.mp3
```

### `audio-volume-detect-time`
Analyzes an audio file in 0.1-second slices and prints the RMS level (in dB) for each slice alongside a timestamp, giving a time-stamped volume profile of the file.

**Usage:** `audio-volume-detect-time <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The audio file to analyze. |

**Examples:**
```bash
audio-volume-detect-time recording.mp3
```

### `convert-to-mp3`
Converts a video or audio file into an MP3 file using `ffmpeg`, with configurable encoding parameters and optional metadata tagging.

**Usage:** `convert-to-mp3 <video|audio> [target-mp3] [--bitrate <bitrate>] [--sample-rate <sample-rate>] [--channels <channels>] [--strip-metadata] [--title <title>] [--artist <artist>] [--album <album>]`

| Argument / Flag | Description |
|---|---|
| `<video\|audio>` | Source media file to convert (required). |
| `[target-mp3]` | Output MP3 path. If omitted, derives `<source>.mp3`, appending `-1`, `-2`, etc. to avoid overwriting an existing file. |
| `--bitrate <bitrate>` | Audio bitrate in kbps (digits only). Default: 160. |
| `--sample-rate <sample-rate>` | Sample rate in Hz (digits only). Default: 48000. |
| `--channels <channels>` | Number of audio channels (digits only). Default: 2. |
| `--strip-metadata` | Discard all metadata from the source (`-map_metadata -1`). |
| `--title <title>` | Set the MP3 title metadata tag. |
| `--artist <artist>` | Set the MP3 artist metadata tag. |
| `--album <album>` | Set the MP3 album metadata tag. |

**Examples:**
```bash
convert-to-mp3 lecture.mp4
convert-to-mp3 song.flac out.mp3 --bitrate 320 --sample-rate 44100
convert-to-mp3 interview.wav --strip-metadata --title "Episode 1" --artist "Jane Doe"
```

### `play-track`
Plays one or more audio files quietly through `mpg123`, accepting file paths as arguments or a whitespace-separated list on stdin.

**Usage:** `play-track <files or - for stdin>`

| Argument / Flag | Description |
|---|---|
| `<files>` | One or more audio file paths to play. |
| `-` | Read the list of files from stdin instead of arguments. |

**Examples:**
```bash
play-track song.mp3
play-track track1.mp3 track2.mp3
ls *.mp3 | play-track -
```

### `rec`
Records audio from the default ALSA input via `ffmpeg` into a temporary MP3 file, stopping when Enter is pressed (or cleaning up and aborting on interrupt), then prints the recording's path.

**Usage:** `rec`

Takes no arguments.

**Examples:**
```bash
rec
track="$(rec)"
```

### `readme`
Reads typed text aloud: collects the text in [prompt](#prompt)'s multi-line editor (Ctrl-D when done), asks for confirmation, converts the text to speech via an OpenAI or ElevenLabs TTS engine, and plays the resulting MP3.

**Usage:** `readme [--tts <11labs|openai>] [-r|--repeat] [-v|--voice <voice name>]`

| Argument / Flag | Description |
|---|---|
| `--tts <11labs\|openai>` | TTS engine to use. Default: `openai`. |
| `-r, --repeat` | Replay the last generated audio and exit. |
| `-v, --voice <voice name>` | Voice to use (defaults: `nova` for openai, `Dorothy` for 11labs). |
| `--bash-completion <command>` | Output shell-completion candidates. |

**Examples:**
```bash
readme
readme --tts 11labs --voice Dorothy
readme --repeat
```

---

## Webcam

### `cam`
Interactive terminal tool for live-adjusting webcam V4L2 settings (brightness, contrast, saturation, hue, gamma, white balance, backlight compensation) via single keypresses, and for applying or storing camera presets through `cam-settings`.

**Usage:** `cam`

Takes no arguments. Once running, it reads single keys in a loop:

| Key | Description |
|---|---|
| Arrow Up / Down | Increase / decrease brightness |
| Arrow Left / Right | Decrease / increase contrast |
| Page Up / Down | Increase / decrease saturation |
| `,` / `.` | Decrease / increase gamma |
| `+` / `#` | Increase / decrease hue |
| `-` / `_` | Increase / decrease backlight compensation |
| `ü` / `ä` | Increase / decrease white balance temperature (disables auto white balance first) |
| `ö` | Toggle automatic white balance on/off |
| `r` | Reset all settings to camera defaults |
| `d` | Apply the `default` preset (if present) |
| `b`, `B`, `n`, `N` | Apply the 1st–4th non-default preset (if present) |
| `p` | Pick a preset to apply from a list |
| `P` | Prompt for a name, completing against the existing presets, and store the current settings under it |
| `h` | Print the key-binding help again |

**Examples:**
```bash
cam
```

### `cam-settings`
Reads and writes webcam controls through `v4l2-ctl`, supporting getting/setting/increasing/decreasing/resetting individual settings as well as listing, showing, applying, and storing named presets under `~/.config/cam-settings`.

**Usage:** `cam-settings [--list-settings] [--list-keys <setting>] set <setting> <value> | get [-r|--raw] <setting> | increase <setting> | decrease <setting> | reset <setting> | preset list|apply|store|show <name>`

| Argument / Flag | Description |
|---|---|
| `--list-settings` | List the names of all available camera settings. |
| `--list-keys <setting>` | List the properties (min, max, step, value, default, etc.) of the given setting. |
| `set <setting> <value>` | Set a setting to a specific value. |
| `get [-r\|--raw] <setting>` | Print a setting's current value; `-r`/`--raw` prints only the bare value without the leading `setting:` label. |
| `increase <setting>` | Increase a setting by one step (clamped to its maximum). |
| `decrease <setting>` | Decrease a setting by one step (clamped to its minimum). |
| `reset <setting>` | Reset a setting to its default value. |
| `preset list` | List the names of stored presets. |
| `preset apply <name>` | Apply a stored preset to the camera. |
| `preset store <name>` | Store the current camera settings as a named preset. |
| `preset show <name>` | Print the raw contents of a stored preset. |

Preset names are sanitized so any non-alphanumeric character becomes an underscore.

**Examples:**
```bash
cam-settings set brightness 128
cam-settings get --raw white_balance_automatic
cam-settings preset store "evening light"
cam-settings preset apply evening_light
```

---

## Clipboard

### `clip`
Copies text from a file or stdin into the clipboard, handling both Wayland (`wl-copy`) and X11 (`xclip`), with options to target the clipboard and/or primary selection, strip newlines, and optionally echo the content.

**Usage:** `clip [--print] [-c|--clipboard|-p|--primary] [-n|--no-newline] [<file, or stdin>]`

| Argument / Flag | Description |
|---|---|
| `--print` | Also print the copied content to stdout. |
| `-c, --clipboard` | Copy to the clipboard selection only (default is both clipboard and primary). |
| `-p, --primary` | Copy to the primary selection only. |
| `-n, --no-newline` | Strip all newline and carriage-return characters before copying. |
| `<file>` | File to copy; if omitted (or `-`), content is read from stdin. |

**Examples:**
```bash
clip notes.txt
git rev-parse HEAD | clip -c -n
echo "hello" | clip --print
```

### `clip-clear`
Clears the contents of the clipboard or primary selection on either Wayland or X11.

**Usage:** `clip-clear [-c|--clipboard|-p|--primary]`

| Argument / Flag | Description |
|---|---|
| `-c, --clipboard` | Clear the clipboard selection (default). |
| `-p, --primary` | Clear the primary selection. |

**Examples:**
```bash
clip-clear
clip-clear --primary
```

### `clip-files`
Copies the names and contents of one or more files into the clipboard (via `clip`), optionally wrapping each file's content in a Markdown code block.

**Usage:** `clip-files [-m|--markdown] <files ...>`

| Argument / Flag | Description |
|---|---|
| `-m, --markdown` | Wrap each file's content in triple-backtick Markdown code blocks. |
| `<files ...>` | One or more files whose name and content are copied. |

**Examples:**
```bash
clip-files main.go util.go
clip-files --markdown README.md
```

### `clip-image`
Reads a file path from stdin, determines its MIME type, and copies the file into the clipboard as that type (useful for putting an image on the clipboard) on either Wayland or X11.

**Usage:** `<command producing a file path> | clip-image`

Takes no arguments; requires a file path piped in on stdin.

**Examples:**
```bash
echo /path/to/screenshot.png | clip-image
clip-paste-image | clip-image
```

### `clip-paste`
Prints the current clipboard or primary-selection contents to stdout or a file, on either Wayland or X11, with an option to ensure a trailing newline.

**Usage:** `clip-paste [-n|--new-line] [-c|--clipboard|-p|--primary] [-f|--file <file>]`

| Argument / Flag | Description |
|---|---|
| `-n, --new-line` | Ensure the output ends with a trailing newline. |
| `-p, --primary` | Read from the primary selection (default). |
| `-c, --clipboard` | Read from the clipboard selection. |
| `-f, --file <file>` | Write the contents to the given file instead of stdout. |

**Examples:**
```bash
clip-paste
clip-paste --clipboard --new-line
clip-paste -c -f out.txt
```

### `clip-paste-collect`
Repeatedly reads the clipboard, appends each new value to a file (or stdout), clears the clipboard, and waits for the next change, effectively accumulating a log of everything copied; built on `clip-paste-wait` and `clip-clear`.

**Usage:** `clip-paste-collect [-h|--help] [--verbose] [-r|--clear] [-c|--clipboard|-p|--primary] [FILE]`

| Argument / Flag | Description |
|---|---|
| `--verbose` | Print progress and each collected value (prefixed with `>>`) to stderr. |
| `-r, --clear` | Clear the clipboard once before starting the collection loop. |
| `-c, --clipboard` | Operate on the clipboard selection. |
| `-p, --primary` | Operate on the primary selection. |
| `FILE` | Optional output file; its parent directory is created if needed. Defaults to stdout. |

**Examples:**
```bash
clip-paste-collect
clip-paste-collect -r --verbose -c collected.txt
```

### `clip-paste-image`
Extracts an image from the clipboard (or downloads it if the clipboard holds an http(s) URL), saves it to a temporary file with the correct extension, optionally converts it to JPEG, and prints the resulting file path; works on Wayland or X11.

**Usage:** `clip-paste-image [--jpg]`

| Argument / Flag | Description |
|---|---|
| `--jpg` | Convert the extracted image to JPEG (via `convert`) before printing its path. |

**Examples:**
```bash
clip-paste-image
saved="$(clip-paste-image --jpg)"
```

### `clip-paste-wait`
Polls the clipboard (or primary selection) once per second and prints its contents as soon as it becomes non-empty, on either Wayland or X11.

**Usage:** `clip-paste-wait [-h|--help] [-p|--primary|-c|--clipboard]`

| Argument / Flag | Description |
|---|---|
| `-c, --clipboard` | Wait on and read from the clipboard selection (default). |
| `-p, --primary` | Wait on and read from the primary selection. |

**Examples:**
```bash
clip-paste-wait
clip-paste-wait --primary
```

### `copy-base64`
Base64-encodes a file and copies a self-contained reconstruction command to the clipboard, so pasting and running it elsewhere recreates the original file.

**Usage:** `copy-base64 <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The file to encode and turn into a clipboard reconstruction command (required). |

**Examples:**
```bash
copy-base64 config.tar.gz
copy-base64 ./secret-key.pem
```

### `serve-clip`
Restarts a BusyBox HTTP server on port 9090 serving `~/Dokumente/html/`, clearing the clipboard first.

**Usage:** `serve-clip`

Takes no arguments.

**Examples:**
```bash
serve-clip
```

---

## AI Helpers

### `agent-session`
Browses and prints conversation sessions of the Claude CLI (`~/.claude/projects`) and the Codex CLI (`~/.codex/sessions`), showing user and agent messages and rendering them as Markdown (via `glow`) unless raw output is requested. With no session argument, a colorful `fzf-with-header` picker lists each session's agent, age, generated title, and directory by last activity. Titles come from Claude's generated `ai-title` records and Codex's thread database, falling back to the first prompt for sessions without one, so the prompt gets no column of its own by default; it stays a hidden searchable field of the picker and its width goes to the title, which is displayed in a 50-character column. `--prompt-column` shows the prompt as a column as well, which shortens the title column to 30 characters; `--print` uses 50/60-character columns. The complete title and prompt are kept in hidden fields, so a search matches them in full. The newest 20 sessions load first; once the picker opens, the rest of the selected range loads in the background. Claude and Codex use distinct agent colors, with a fallback color for additional agents. Ages under 60 minutes are green and italic; older ages are faded. Seconds are omitted after 60 seconds, minutes from two hours onward, and hours from two days onward; all ages of a listing are rendered and colored by one `toage` call against the same reference point, which gets the two colors of the column handed over. Session IDs stay hidden. The preview renders the selected conversation through `glow` with color forced on.

**Usage:** `agent-session [OPTIONS] [SESSION]`

| Argument / Flag | Description |
|---|---|
| `SESSION` | The ID of the session to print; omit to browse sessions interactively. |
| `-h, --help` | Show the help message and exit. |
| `-a, --agent AGENT` | Only use sessions of `claude` or `codex` (default: both). |
| `-l, --last` | Print the latest session. |
| `-n, --limit LIMIT` | Limit sessions by count instead of the default age cutoff; cannot be combined with `--days`. |
| `-d, --days DAYS` | Only list sessions active within the last `DAYS` days (default: 10); cannot be combined with `--limit`. |
| `-A, --all-directories` | List sessions from all recorded working directories instead of only the current directory. |
| `-p, --print` | Print the formatted session table instead of opening the interactive picker. |
| `-P, --prompt-column` | Show the first prompt as a column of its own; without it the prompt stays searchable in the picker. |
| `-g, --grep GREP` | Filter listed sessions to those whose user or agent messages match the given regex. |
| `-i, --igrep GREP` | Filter listed sessions by a case-insensitive regex match in their messages. |
| `-r, --raw` | Print raw output instead of rendering it through `glow`. |
| `--bash-completion` | Output shell-completion candidates (flags, agent names and session IDs). |
| `--verbose` | Print verbose diagnostic output to stderr. |

By default, listings include sessions from the current directory active within the last 10 days. `--all-directories` includes every recorded working directory. `--days` changes the age window; `--limit` instead lists the newest requested number without an age cutoff. Filtering matches the messages only, so hits in tool calls, tool output or file contents do not list a session. The session files are grepped first to narrow down the candidates, which are then confirmed against their decoded messages, newest session first. Non-ASCII characters are stored escaped in some session files and are not found by the pre-filter.

Called as `claude-session` or `codex-session` (symlinks) the matching agent is preselected; `--agent` still overrides it.

The picker binds `/` to prompt for a case-insensitive message search, `enter` to print rendered Markdown, `alt-enter` to print raw Markdown, `ctrl-c` to copy raw Markdown to the clipboard, `tab` to toggle between all folders and the current folder, `ctrl-f` to fork, `ctrl-x` to resume the session in its own directory, `alt-x` to continue it in the current directory, `ctrl-r` to refresh the session list and preview, and `esc` to exit.

`alt-x` continues a session of another folder in the one the picker was started from, which is what browsing all folders is usually for. Both CLIs look a session up in the project of their working directory, so this only continues the session itself where the agent can be told which directory to work in: `codex resume -C DIR ID` does that, and a session of the current folder resumes natively anyway. For a claude session of another folder the conversation is handed to a fresh session in the current directory as context, the same way a fork into another agent works.

Searching and switching the folder scope happen inside the running picker instead of it being closed and opened again: the scope and the search live in a state file the list command reads, so a key only changes that file and reloads the list - showing the newest 20 sessions again and loading the rest in the background, the way the picker started. The prompt names what is shown, the folder of the current directory or `all` in the color of the directory column, followed by `~ PATTERN` in the color of the title column while a search is active, and then the arrow of the picker in its own color; so the scope and the search stay visible, while the fzf filter and the cursor are kept as they are. The search prompt is pre-filled with the active pattern, so it can be edited or emptied to clear the search; an aborted prompt keeps it. `backspace` clears the search as well, but only while there is one - without a search it stays the key that erases the fzf filter. The clipboard confirmation and the exact resume or fork command are printed in a muted color. Resume starts `codex resume ID` or `claude --resume ID` from the session's recorded working directory with standard input, output, and error reattached to the terminal.

Fork prompts for the target agent with completion over `claude` and `codex`, defaulting to the session's current agent. Same-agent forks use the CLI's native fork support (`codex fork` or Claude's `--fork-session`). Cross-agent forks include the complete rendered conversation context and launch the target in the original working directory. Claude can open directly at an empty prompt with the context injected as additional system instructions. Codex receives the context as an initial wait-for-the-user prompt; unusually large transcripts are loaded from a temporary file to avoid command-line size limits. `shift-enter` is unavailable because fzf does not expose it as a distinct key.

**Examples:**
```bash
agent-session
agent-session --print
agent-session --last
agent-session --days 7
agent-session --all-directories
agent-session --prompt-column
agent-session --agent codex -n 10 --grep "TODO"
agent-session 3f9a1c2b-abcd-1234-ef56-7890abcdef12 --raw
claude-session -n 20 --igrep "docker compose"
codex-session --last
```

### `aish`
Edits or creates a file or command using an AI CLI tool, runs a syntax check, and shows a diff. The CLI to run is picked with completion over `codex`, `claude` and `opencode` (default `claude`), and any other command can be typed instead.

Symlinks are resolved first. If the resulting file lives inside a git repository, the AI CLI is started in that repository and edits the file in place — no temporary repository is created and nothing has to be copied back. Change detection compares `HEAD` and `git status --porcelain` against the state from before the run, so a repository that was already dirty is not mistaken for changes made by the agent. Afterwards the repository path, the current branch and `git status --short --branch` are printed and a selection asks what should happen with the repository: nothing, push the changes with `git-push` or move them to a new branch with `git-change`. Otherwise the file is copied into a temporary git repository (together with `bash-cli-instructions.md`) and copied back to the original location after the changes have been confirmed, using sudo when the target folder is not writable.

**Usage:** `aish [OPTIONS] COMMAND`

| Argument / Flag | Description |
|---|---|
| `COMMAND` | The command or file to edit. Absolute paths (`/`) and relative paths (`./`) are used directly; otherwise resolved via `which`, falling back to `/usr/local/bin/<COMMAND>`. |
| `-h, --help` | Show the help message. |
| `--bash-completion` | Output shell-completion candidates (flags plus every command in `PATH`). |

**Examples:**
```bash
aish backup-single-file
aish /usr/local/bin/my-script
aish ./new-tool
```

### `claude-session`
Symlink to [`agent-session`](#agent-session) that only uses sessions of the Claude CLI.

### `codex-chat`
Sends a prompt to the Codex AI CLI (run in `--full-auto exec` mode and instructed to ground answers with web search), automatically creating or resuming a per-TTY session and storing chat logs under `~/.codex-chat`.

**Usage:** `codex-chat [OPTIONS] PROMPT...`

| Argument / Flag | Description |
|---|---|
| `PROMPT...` | The prompt text to send; words are joined into a single prompt. |
| `-h, --help` | Display the help message and exit. |
| `-c, --clip` | Insert the current clipboard contents into the prompt; repeatable. |
| `-f, --file <file>` | Insert the contents of a file into the prompt (use `-` for stdin); repeatable. |
| `-r, --resume <id>` | Resume a specific session ID, overriding the current TTY session. |
| `--print-last` | Print the most recent chat log and exit. |
| `--print-current` | Print the current TTY session's chat log and exit. |
| `--print-history` | Print a table of all past chat logs (ID and prompt) and exit. |

**Examples:**
```bash
codex-chat What is the capital of France?
codex-chat I see this error: -c What is wrong here? Maybe look at -f somefile
cat error.log | codex-chat Can you analyze this error log? -f -
codex-chat --print-history
```

### `codex-session`
Symlink to [`agent-session`](#agent-session) that only uses sessions of the Codex CLI.

### `vish`
Edits or creates a file or command in vim (using sudo when needed), making new files executable bash scripts, handling vim swap-file recovery, and running a syntax check on save with the option to re-edit.

**Usage:** `vish [-h] COMMAND`

| Argument / Flag | Description |
|---|---|
| `COMMAND` | The file or command to edit. Absolute (`/...`) and relative (`./...`) paths are used directly; otherwise resolved via `which`, falling back to `/usr/local/bin/COMMAND`. |
| `-h, --help` | Show the help message and exit. |
| `--bash-completion` | Output shell-completion candidates (flags plus every command in `PATH`). |

**Examples:**
```bash
vish my-script
vish ./local-tool
vish /usr/local/bin/some-command
```

---

## Color and Terminal Text Styling

### `color-parse`
Converts a color/style specification into ANSI escape codes, optionally wrapping supplied text (or piped stdin) with the codes and a trailing reset; supports named colors, 256-color indices, hex (`#rrggbb` / `0xrgb`), `rgb(...)`, `fg=`/`bg=` keys, text styles, and `raw(...)` passthrough codes.

**Usage:** `color-parse [-n] <color_spec|end> [text...]`

| Argument / Flag | Description |
|---|---|
| `color_spec` | A colon-separated style spec, e.g. `fg=red:bold`, `gray:italic`, `#c0ffee`, or `rgb(255,0,0):bold`. |
| `end` | The literal word `end`, which prints only the ANSI reset code. |
| `text...` | Optional text to print wrapped in the color codes; if omitted and stdin is piped, the piped text is colored instead. |
| `-n, --newline` | Always print a trailing newline at the end of the output. |
| `-h, --help` | Show the help/usage message and exit. |

**Examples:**
```bash
color-parse "gray:italic"
color-parse "fg=white:bold:underline" "Hello World"
color-parse "#c0ffee" "Colored text"
color-parse end
echo -e "hi" | color-parse red
```

#### Symlink alias family
`color-parse` changes behavior based on the name it is invoked as (`argv[0]`). When invoked through a symlink, it derives an environment-variable name from the link name (uppercased, dashes → underscores) and uses that variable's value as the color spec; if unset, it errors out.

- `color-*` aliases look up the matching `COLOR_*` variable (e.g. `color-text-muted` reads `$COLOR_TEXT_MUTED`) and emit codes + text **without** a forced trailing newline.
- `print-*` aliases map to the same `COLOR_*` variable but **always append** a trailing newline.

| Alias family | Environment variable(s) | Purpose |
|---|---|---|
| `color-text-default` / `print-text-default` | `COLOR_TEXT_DEFAULT` | Default body text style. |
| `color-text-bold` / `print-text-bold` | `COLOR_TEXT_BOLD` | Bold text. |
| `color-text-italic` / `print-text-italic` | `COLOR_TEXT_ITALIC` | Italic text. |
| `color-text-muted` / `print-text-muted` | `COLOR_TEXT_MUTED` | Muted/de-emphasized text. |
| `color-text-faded` / `print-text-faded` | `COLOR_TEXT_FADED` | Faded text. |
| `color-text-info` / `print-text-info` | `COLOR_TEXT_INFO` | Informational text. |
| `color-text-code` / `print-text-code` | `COLOR_TEXT_CODE` | Inline code snippet, as [glow](https://github.com/charmbracelet/glow) renders `` `code` `` (`203:bg=236`). Used by [prompt](#prompt) for quoted spans. |
| `color-text-success[-light\|-strong]` (+ `print-*`) | `COLOR_TEXT_SUCCESS[_LIGHT\|_STRONG]` | Success text, three intensities. |
| `color-text-warning[-light\|-strong]` (+ `print-*`) | `COLOR_TEXT_WARNING[_LIGHT\|_STRONG]` | Warning text, three intensities. |
| `color-text-error[-light\|-strong]` (+ `print-*`) | `COLOR_TEXT_ERROR[_LIGHT\|_STRONG]` | Error text, three intensities. |
| `color-text-numeric[-light\|-strong]` (+ `print-*`) | `COLOR_TEXT_NUMERIC[_LIGHT\|_STRONG]` | Numeric value text, three intensities. |
| `color-table-header` / `print-table-header` | `COLOR_TABLE_HEADER` | Table header styling. |
| `color-table-column-1`…`-6` / `print-table-column-1`…`-6` | `COLOR_TABLE_COLUMN_1`…`_6` | Per-column table cell styling. |

### `color-clear`
Strips ANSI escape sequences (colors, styles, cursor codes) from text read on stdin, writing the cleaned text to stdout.

**Usage:** `color-clear` (reads stdin, writes stdout)

Takes no arguments.

**Examples:**
```bash
some-colorful-command | color-clear
color-clear < colored.log > plain.log
```

### `color-reset-bw`
Rewrites ANSI escape sequences read on stdin so that pure black and pure white foreground colors (codes `30`, `97`, `38;5;0`, `38;5;15`) are reset to the terminal's default color, leaving other colors intact.

**Usage:** `color-reset-bw` (reads stdin, writes stdout)

Takes no arguments.

**Examples:**
```bash
some-colorful-command | color-reset-bw
color-reset-bw < colored.log > readable.log
```

---

## Text and Data Processing

### `number`
Prepends line numbers to text read from stdin, with a configurable suffix and optional right-alignment of the numbers.

**Usage:** `number [--suffix|-s <suffix, default: '. '>] [--align|-a]`

| Argument / Flag | Description |
|---|---|
| `--suffix, -s <suffix>` | String placed after each line number (default: `. `). |
| `--align, -a` | Right-align the numbers by padding to the width of the largest line number. |

**Examples:**
```bash
cat list.txt | number
cat list.txt | number --align
cat list.txt | number -s ') '
```

### `table`
Formats tab-separated input from stdin into an aligned, tab-separated table with the given column headers.

**Usage:** `table [-h] HEADER`

| Argument / Flag | Description |
|---|---|
| `HEADER` | Comma-separated list of column header names. |
| `-h, --help` | Show the help message and exit. |

**Examples:**
```bash
printf 'a\t1\nb\t2\n' | table "Name,Value"
```

### `tsv`
Converts a space-separated table on stdin into a tab-separated table (collapsing runs of two or more spaces into tabs), after stripping color codes.

**Usage:** `tsv [-h]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Display the help message and exit. |

**Examples:**
```bash
ls -l | tsv
```

### `tohex`
Reads data from stdin and prints a numbered hex dump (offsets plus uppercase, space-grouped bytes) with a configurable line width.

**Usage:** `tohex [--width|-w <width>]`

| Argument / Flag | Description |
|---|---|
| `-w, --width <width>` | Number of bytes per line; must be even (divisible by 2). Defaults to 8. May also be given as a bare positional argument. |

**Examples:**
```bash
echo -n "hello world" | tohex
echo -n "hello world" | tohex -w 16
cat file.bin | tohex 4
```

### `ocr`
Extracts text from an image file using Tesseract OCR (via `tesserocr`), with selectable recognition language.

**Usage:** `ocr [-l|--language LANGUAGE] image-path`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the help message and exit. |
| `-l, --language LANGUAGE` | Language to use for OCR (default: `eng`); must be a Tesseract language installed on the system. |
| `image-path` | Path to the image file to read text from. |

**Examples:**
```bash
ocr scan.png
ocr --language deu document.jpg
```

### `hgrep`
Greps your shell history case-insensitively (using `history_read`), stripping leading ISO timestamps and excluding prior `hgrep` invocations, with optional grep-style context lines.

**Usage:** `hgrep [options] <pattern ...>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the help message and exit. |
| `-B <n>, --before-context=<n>` | Show `n` lines before each match. |
| `-A <n>, --after-context=<n>` | Show `n` lines after each match. |
| `-C <n>, --context=<n>` | Show `n` lines of context around each match. |
| `<pattern ...>` | The search pattern (multiple words are joined with spaces); at least one required. |

**Examples:**
```bash
hgrep docker
hgrep -C 3 git rebase
hgrep --after-context=2 ssh
```

### `ygrep`
Greps YAML documents (including Kubernetes-style lists) read from stdin, matching a regex against each resource and printing selected fields alongside the matching lines, with grep-like context options.

**Usage:** `ygrep [-i] [-f FIELD] [-m N] [-C N] [-B N] [-A N] [-L | -l] <pattern>`

| Argument / Flag | Description |
|---|---|
| `pattern` | Regex pattern to search for within each YAML resource. |
| `-i, --ignore-case` | Case-insensitive search. |
| `-f, --fields FIELD` | YAML field(s) to print as a prefix; repeatable. Defaults to `name`, or `metadata.namespace` + `metadata.name` when available. |
| `-m, --max-count N` | Maximum number of matches to print per resource. |
| `-C, --context N` | Print `N` lines of context before and after each match. |
| `-B, --before-context N` | Print `N` lines of context before each match. |
| `-A, --after-context N` | Print `N` lines of context after each match. |
| `-L, --fields-without-matches` | Print only the fields of resources with no match. |
| `-l, --fields-with-matches` | Print only the fields of resources that have a match. |

`-l` and `-L` are mutually exclusive, and neither can be combined with context or `--max-count`.

**Examples:**
```bash
kubectl get pods -o yaml | ygrep -i imagepullbackoff
kubectl get deploy -o yaml | ygrep -l -f metadata.name 'replicas: 0'
cat resources.yaml | ygrep -C 2 'image:'
```

### `paginate`
Automates reading multiple pages from a paginating command, auto-detecting the page-index and page-size argument names (from the command's `--help`) and stopping on an empty result, an empty JSON/null result, or a configured page/item limit.

**Usage:** `paginate [OPTIONS] COMMAND [ARGUMENTS]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the help message and exit. |
| `-S, --page-size <n>` | Items per page (numeric); defaults to 50. |
| `-M, --max-items <n>` | Stop after enough whole pages to cover this many items (numeric). |
| `-P, --max-pages <n>` | Maximum number of pages to read (numeric). |
| `-p, --page-index-argument <name>` | Name of the page-index argument; auto-detected if omitted. |
| `-s, --page-size-argument <name>` | Name of the page-size argument; auto-detected if omitted. |
| `--verbose` | Print the commands being run and detection details to stderr. |
| `--` | Marks the end of options; everything after is the command and its arguments. |
| `COMMAND [ARGUMENTS]` | The command to invoke per page, with its arguments. |

**Examples:**
```bash
paginate glab issue list --state opened
paginate --page-size 100 --max-items 500 nexus-cli search
paginate -p --page -s --limit -- my-api-tool list --format json
```

### `loop`
Reads stdin line by line and runs a command template for each line, substituting placeholders for the whole line, a line index, and (with a delimiter) individual fields.

**Usage:** `loop [-d "<delimiter>"] '<commands>'`

| Argument / Flag | Description |
|---|---|
| `-d "<delimiter>"` | Single-character field delimiter used to split each line into fields. |
| `'<commands>'` | Command template run per line. Supports `{}` (whole line), `{i}` (zero-based index), and, with a delimiter, `{0}`–`{9}` (fields) and `{n}` (field count). |

**Examples:**
```bash
ls | loop 'echo file: {}'
cat data.csv | loop -d ',' 'echo row {i}: col1={1} col2={2} of {n}'
```

### `read-in-chunks`
Reads stdin and pipes it into a command in fixed-size chunks of lines, pausing after each full chunk to ask (on the terminal) whether to continue.

**Usage:** `read-in-chunks <lines> <command>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show usage and exit. |
| `<lines>` | Number of lines per chunk (must be > 0). |
| `<command>` | The command each chunk is piped into (run via `eval`). |

**Examples:**
```bash
cat urls.txt | read-in-chunks 10 'xargs -n1 curl -sO'
some-command | read-in-chunks 50 'wc -l'
```

### `base64-find`
Scans a file line by line and prints those lines that contain a base64-encoded string which decodes to printable UTF-8 text longer than 10 characters.

**Usage:** `base64-find <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The file to search for base64-encoded strings. |
| `-h, --help` | Show the help message. |

**Examples:**
```bash
base64-find config.env
base64-find secrets.txt
```

---

## Format, Encoding and Conversion

### `csv2md`
Parses one or more CSV files into Markdown tables (a launcher wrapper around the `csv2md` Python package).

**Usage:** `csv2md [-d DELIMITER] [-q QUOTECHAR] [-C COLUMNS] [-c [COLS ...]] [-r [COLS ...]] [-H] [CSV_FILE ...]`

| Argument / Flag | Description |
|---|---|
| `[CSV_FILE ...]` | One or more CSV files to parse (reads stdin if none given). |
| `-h, --help` | Show help and exit. |
| `-d, --delimiter DELIMITER` | Delimiter character. Default: `,`. |
| `-q, --quotechar QUOTECHAR` | Quotation character. Default: `"`. |
| `-C, --columns COLUMNS` | Comma-separated list of zero-based column indices or ranges, e.g. `"0,3-5,7"`. |
| `-c, --center-aligned-columns [COLS ...]` | Zero-based column numbers to center-align. |
| `-r, --right-aligned-columns [COLS ...]` | Zero-based column numbers to right-align. |
| `-H, --no-header-row` | Treat input as having no header row; generates default Excel-style headers. |

**Examples:**
```bash
csv2md data.csv > data.md
csv2md -d ';' -r 2 3 sales.csv
csv2md -H -C "0,2-4" export.csv
```

### `markdown-table`
Converts a tab- or space-separated table from stdin into a Markdown table, or (with a flag) converts a Markdown table back into tab- or comma-separated values.

**Usage:** `markdown-table [OPTIONS]`

| Argument / Flag | Description |
|---|---|
| `--to-tsv` | Convert a Markdown table (stdin) to tab-separated values. |
| `--to-csv` | Convert a Markdown table (stdin) to comma-separated values. |
| `-h, --help` | Show the help message and exit. |

With no option, input is treated as a tab/space-separated table (columns split on a tab or two-or-more spaces, first row is the header) and converted to a Markdown table. Empty/filler header cells still get a valid separator (`---`). Multiple tables are supported: two or more blank lines end a table, and the next non-blank row starts a new table with its own header. `--to-tsv` and `--to-csv` are mutually exclusive.

**Examples:**
```bash
printf 'Name\tAge\nAlice\t30\n' | markdown-table
cat table.md | markdown-table --to-csv
cat table.md | markdown-table --to-tsv
```

### `markdown-to-html`
Converts Markdown read from stdin into HTML using `pandoc`.

**Usage:** `markdown-to-html`

Takes no arguments.

**Examples:**
```bash
cat README.md | markdown-to-html > README.html
echo '# Title' | markdown-to-html
```

### `markdown-to-rtf`
Converts Markdown read from stdin into RTF using `pandoc`.

**Usage:** `markdown-to-rtf`

Takes no arguments.

**Examples:**
```bash
cat notes.md | markdown-to-rtf > notes.rtf
echo '**bold**' | markdown-to-rtf
```

### `slack-mrkdwn`
Converts a Markdown file (or stdin) into Slack's mrkdwn format and prints it to stdout.

**Usage:** `slack-mrkdwn -f FILE`

| Argument / Flag | Description |
|---|---|
| `-f, --file FILE` | The Markdown file to convert, or `-` to read from stdin (required). |

**Examples:**
```bash
slack-mrkdwn -f notes.md
cat notes.md | slack-mrkdwn -f -
```

### `jsonformat`
Formats a JSON file in place using `jq`, with optional recursive sorting of object keys either everywhere or under specific paths.

**Usage:** `jsonformat [OPTIONS] JSON_FILE`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the help message and exit. |
| `--sort-all-keys` | Sort object keys recursively at all levels. |
| `--sort-keys PATH` | Sort object keys recursively under the given dot-notation `PATH` (e.g. `.models[].scores`). Repeatable. |
| `JSON_FILE` | Path to the JSON file to format in place (must exist and be writable). |

**Examples:**
```bash
jsonformat data.json
jsonformat --sort-all-keys config.json
jsonformat --sort-keys '.models' --sort-keys '.models[].scores' report.json
```

### `kmlformat`
Pretty-prints a KML file by reformatting its XML and breaking each set of coordinates onto separate, indented lines.

**Usage:** `kmlformat <kml-file>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the usage message and exit. |
| `<kml-file>` | Path to the KML file to format. |

**Examples:**
```bash
kmlformat route.kml
```

### `htmlentities`
Encodes or decodes HTML entities from stdin using Perl's `HTML::Entities` module (decoding also converts non-breaking spaces to regular spaces).

**Usage:** `htmlentities [--decode|-d] [--encode|-e]`

| Argument / Flag | Description |
|---|---|
| `-e, --encode` | Encode HTML entities read from stdin (default mode). |
| `-d, --decode` | Decode HTML entities read from stdin. |

**Examples:**
```bash
echo '<a href="x">' | htmlentities --encode
echo '&lt;a&gt;' | htmlentities -d
```

### `image-base64`
Reads an image file and prints it as a base64-encoded `data:` URL (with a fixed `image/jpeg` MIME type).

**Usage:** `image-base64 <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | Path to the image file to encode. |

**Examples:**
```bash
image-base64 logo.png
echo "<img src=\"$(image-base64 logo.png)\">"
```

### `excel-extract`
Extracts and prints the formulas, cell values, VBA macro code, and defined names/custom functions from an Excel workbook.

**Usage:** `excel-extract <xlsm_file>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show help and exit. |
| `<xlsm_file>` | Path to the Excel file to extract content from (required). |

**Examples:**
```bash
excel-extract report.xlsm
excel-extract /path/to/model.xlsx
```

### `parse-excel-date`
Parses a German abbreviated month/year string (the kind Excel produces, e.g. `Mrz 24`) and prints it as an ISO date (`YYYY-MM-DD`).

**Usage:** `parse-excel-date <date string>`

| Argument / Flag | Description |
|---|---|
| `date` | One or more tokens forming the Excel date string (joined with spaces), e.g. `Mrz 24`. |
| `-h, --help` | Show the help message. |

**Examples:**
```bash
parse-excel-date "Mrz 24"
parse-excel-date Jan 25
```

### `toage`
Turns timestamps into compact, human readable ages: `5d`, `2h13m`, `47s`. Without arguments it works as a filter and replaces every ISO 8601 timestamp found on stdin by its age, which is what the table output of other tools is piped through. With `TIME` arguments, or with `--lines`, it prints one age per line instead, so a whole column can be rendered by a single call. The precision can shrink as a span grows: `--drop-seconds`, `--drop-minutes` and `--drop-hours` name the span from which on that unit is left out. Weeks are opt-in, so days keep accumulating (`41d3h`) unless `--units wdhms` is given (`5w6d`). It is installed as a command and as the importable `toage` Python module (`toage()`, `format_span()`), which is how `k-format` renders its age column.

**Usage:** `toage [OPTIONS] [TIME ...]`

| Argument / Flag | Description |
|---|---|
| `TIME` | ISO 8601 timestamp or epoch seconds to print the age of, one age per line; omit to filter stdin. |
| `-h, --help` | Show the help message and exit. |
| `-n, --now TIME` | Reference point instead of the current time, so a batch of ages stays consistent. |
| `-U, --units UNITS` | Units that may appear, largest first; a unit left out rolls into the next smaller one (default: `dhms`). |
| `-u, --max-units N` | Print at most `N` units, `0` for all (default: 2). |
| `--drop-seconds SPAN` | Leave out seconds from `SPAN` on, `never` to always keep them (default: `1h`). |
| `--drop-minutes SPAN` | Leave out minutes from `SPAN` on (default: `never`). |
| `--drop-hours SPAN` | Leave out hours from `SPAN` on (default: `never`). |
| `-m, --min SPAN` | Shortest span to report, so anything younger is still printed as `SPAN` instead of as nothing (default: `0`, which prints nothing). |
| `-c, --color RULE` | Color spans below `SPAN`, as `SPAN=COLOR` or as a plain `COLOR` for every span; repeatable, the first matching rule wins. |
| `-l, --lines` | Read one timestamp or epoch per line from stdin instead of scanning lines for timestamps. |

Spans are written as `90`, `90s`, `2h` or `1d12h`. A timestamp without an offset is read as local time, and one in the future has no age.

Coloring keeps the palette with the caller: `COLOR` is an escape sequence, its written `\033[36m` form, or bare SGR codes like `38;5;6`, and the age is wrapped in it followed by a reset. Rules are checked in the order they are given, so the smallest span comes first and a rule without a span is the fallback for everything above it - one call can therefore highlight a recent age and fade an old one. An empty age stays uncolored.

**Examples:**
```bash
git log --pretty=format:'%h %cI %s' | toage
git log --pretty=format:'%h %cI %s' | toage --color '\033[38;5;6m'
toage 2026-08-10T09:00:00Z 1754812345
toage --units wdhms --min 1s --drop-seconds 1m --drop-minutes 2h --drop-hours 2d 1754812345
toage --color '1h=38;5;40;3' --color '38;5;245' 1754812345
find . -maxdepth 1 -printf '%T@\n' | toage --lines
```

### `file-ext`
Determines a file's appropriate extension from its MIME type, using `/etc/mime.types` plus a small built-in override table (e.g. `audio/mpeg` → `mp3`).

**Usage:** `file-ext <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The file to inspect; its detected extension is printed, or the command exits non-zero if none can be determined. |

**Examples:**
```bash
file-ext downloaded-blob
mv data "data.$(file-ext data)"
```

### `mime-to-ext`
Looks up a MIME type in `/etc/mime.types` and prints its associated file extensions, one per line.

**Usage:** `mime-to-ext <mime-type>`

| Argument / Flag | Description |
|---|---|
| `<mime-type>` | The MIME type to look up (e.g. `image/png`). |

**Examples:**
```bash
mime-to-ext image/png
mime-to-ext application/pdf
```

---

## Files and Shell Command Helpers

### `catsh`
Prints the contents of a script or command, resolving a bare command name through `which` (falling back to `/usr/local/bin/`) so you can quickly view a shell helper without knowing its full path.

**Usage:** `catsh <file|command>`

| Argument / Flag | Description |
|---|---|
| `<file\|command>` | An absolute path, a `./` relative path, or a command name to resolve via `which` and print. |
| `--bash-completion` | Output shell-completion candidates (every command in `PATH`). |

**Examples:**
```bash
catsh clip
catsh ./cam-settings
```

### `cpsh`
Copies one executable/script over another using sudo, resolving each argument through `which` (or falling back to `/usr/local/bin`) when not given as an absolute or `./` path.

**Usage:** `cpsh <command-source> <command-target>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show usage and exit. |
| `<command-source>` | Source command/script (resolved via path, `which`, or `/usr/local/bin/<name>`; must exist). |
| `<command-target>` | Destination command/script, resolved the same way; copied to with `sudo cp -v`. |
| `--bash-completion` | Output shell-completion candidates (flags plus every command in `PATH`). |

**Examples:**
```bash
cpsh ./mytool mytool
cpsh /home/user/bin/deploy deploy
```

### `mvsh`
Moves (renames) one executable to another using `sudo`, resolving each argument via `PATH` (or falling back to `/usr/local/bin`) unless given as an absolute or `./` path.

**Usage:** `mvsh <command-source> <command-target>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the usage message and exit. |
| `<command-source>` | Source command or path to move. |
| `<command-target>` | Target command or path. |
| `--bash-completion` | Output shell-completion candidates (flags plus every command in `PATH`). |

**Examples:**
```bash
mvsh oldtool newtool
mvsh ./local-script /usr/local/bin/installed-script
```

### `sush`
Installs a file or command into `/usr/local/bin` as a root-owned, executable copy, showing a colored diff and prompting before overwriting an existing target, and optionally deleting the source.

**Usage:** `sush <file|command>`

| Argument / Flag | Description |
|---|---|
| `<file\|command>` | A file path, or a command name resolved via `which`, to copy into `/usr/local/bin`. |
| `--bash-completion` | Output shell-completion candidates (every command in `PATH`). |

**Examples:**
```bash
sush ./my-script
sush some-command
```

### `sucp`
Thin wrapper that runs `cp` with `sudo`.

**Usage:** `sucp [cp arguments]`

| Argument / Flag | Description |
|---|---|
| `[cp arguments]` | All arguments are passed through to `sudo cp`. |

**Examples:**
```bash
sucp file.conf /etc/file.conf
sucp -r dir/ /opt/dir/
```

### `sumv`
Thin wrapper that runs `mv` with `sudo`.

**Usage:** `sumv [mv arguments]`

| Argument / Flag | Description |
|---|---|
| `[mv arguments]` | All arguments are passed through to `sudo mv`. |

**Examples:**
```bash
sumv file.conf /etc/file.conf
sumv old-name /opt/new-name
```

### `suvi`
Thin wrapper that runs `vim` with `sudo`.

**Usage:** `suvi [vim arguments]`

| Argument / Flag | Description |
|---|---|
| `[vim arguments]` | All arguments are passed through to `sudo vim`. |

**Examples:**
```bash
suvi /etc/hosts
```

### `cp-diff`
Recursively copies files from a source directory to a destination, showing a [prompt](#prompt) select list (overwrite, skip, or edit via meld) whenever a destination file or symlink already differs from the source, and asking whether to continue after each change.

**Usage:** `cp-diff <source_directory> <destination_directory>`

| Argument / Flag | Description |
|---|---|
| `<source_directory>` | Directory whose files and symlinks are copied (must exist). |
| `<destination_directory>` | Target directory; differing files trigger an interactive prompt. |

**Examples:**
```bash
cp-diff ./dotfiles ~/
cp-diff /etc/myapp/defaults /etc/myapp
```

### `backup-single-file`
Creates a timestamped backup copy of a single file in the same directory and deletes previous backups of that file older than a configurable number of days.

**Usage:** `backup-single-file [--days <days>] <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The file to back up; must be an existing regular file. |
| `--days <days>` | Retention period in days (positive integer); older backups are deleted. Defaults to `7`. |
| `--help` | Show the usage message. |

**Examples:**
```bash
backup-single-file config.yaml
backup-single-file --days 30 /etc/important.conf
```

### `tmpfile`
Creates an empty temporary file matching the given `mktemp` pattern and prints its path.

**Usage:** `tmpfile <pattern>`

| Argument / Flag | Description |
|---|---|
| `<pattern>` | An `mktemp` template/pattern (e.g. `myapp.XXXXXX`) used to generate the filename. |

**Examples:**
```bash
tmpfile myapp.XXXXXX
tmpfile /tmp/data-XXXX.txt
```

### `file-date`
Prints a file's last-modification time as a compact `YYMMDDHHMMSS` timestamp string.

**Usage:** `file-date <file>`

| Argument / Flag | Description |
|---|---|
| `<file>` | The file whose modification time is formatted and printed (required). |

**Examples:**
```bash
file-date report.pdf
mv photo.jpg "photo-$(file-date photo.jpg).jpg"
```

### `get-image`
Downloads a file from an HTTP(S) URL to a temporary file (preserving the original extension) and prints the temp file path.

**Usage:** `get-image <url>`

| Argument / Flag | Description |
|---|---|
| `<url>` | The URL to download; must begin with `http`. Exactly one argument required. |

**Examples:**
```bash
get-image https://example.com/photo.jpg
open "$(get-image https://example.com/diagram.png)"
```

### `curl-cached`
Fetches a URL with curl and caches the response in `/tmp`, serving the cached copy instead of re-fetching while it is younger than the given TTL.

**Usage:** `curl-cached <url> <ttl-seconds>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show usage and exit. |
| `<url>` | The URL to fetch and cache (required). |
| `<ttl-seconds>` | Cache lifetime in seconds (digits only); cache is reused if newer than this. |

**Examples:**
```bash
curl-cached https://api.example.com/data 300
curl-cached https://example.com/feed.xml 60
```

### `go-run`
Creates a temporary Go file from a template, then repeatedly opens it in `vi`, runs it with `go run`, and prompts whether to continue editing, cleaning up the temp file on exit.

**Usage:** `go-run`

Takes no arguments.

**Examples:**
```bash
go-run
```

### `bump-version`
Increments the lowest meaningful numeric component of a version string, preferring the build segment, then the prerelease segment, then a plain integer version, and otherwise bumping the semver patch level; the new version is printed to stdout.

**Usage:** `bump-version <version> [--no-semver]`

| Argument / Flag | Description |
|---|---|
| `<version>` | The version string to increment (e.g. `1.2.3`, `v7`, `1.0.0-rc1`, `1.0.0+build5`). |
| `--no-semver` | Skip the semver validity check, allowing non-semver version strings. |
| `-h, --help` | Show the usage message. |

**Examples:**
```bash
bump-version 1.2.3
bump-version 1.0.0-rc1
bump-version 1.0.0+build5
bump-version v42 --no-semver
```

### `install-git-release`
Downloads a release artifact from a GitHub or GitLab project (resolving repository names via `git-search`, with platform/architecture-aware artifact selection), then installs a chosen binary, a `.deb` package, or a bundled application, with dry-run, post-install hooks, and renaming support.

**Usage:** `install-git-release [OPTIONS] PROJECT`

| Argument / Flag | Description |
|---|---|
| `PROJECT` | Name or URL of the project to install (required). |
| `-h, --help` | Display help and exit. |
| `-p, --pattern PATTERN` | Glob pattern for the release artifact; repeatable. Defaults to a set of Linux/64-bit patterns. |
| `-b, --binary PATTERN` | Pattern of the binary to install from within the artifact. |
| `-n, --name NAME` | Name to install the final binary as (default: original binary name). |
| `-i, --install-path PATH` | Path to install the binary (default: `/usr/local/bin`). |
| `--bundle` | Install the archive as a bundled app rather than a single binary. |
| `--bundle-path PATH` | Path to install bundled app contents (default: `/usr/local/share`). |
| `-c, --post-install CMD` | Command to run after a successful install (in the unpacked dir); repeatable. Receives env vars `INSTALL_PATH`, `BINARY_NAME`, `BINARY_PATH`, `ARTIFACT`, `UNPACK_DIR`. |
| `-y, --yes` | Answer yes to all prompts (non-interactive). |
| `-d, --dry-run` | Trial run: download and inspect but make no changes. |
| `--bash-completion` | Output shell-completion candidates; release tags are offered when `PROJECT` is an explicit repository. |

**Examples:**
```bash
install-git-release fzf
install-git-release --dry-run https://github.com/junegunn/fzf
install-git-release -p '*linux*arm64*' -b 'mytool' -n mt my/project
install-git-release -c 'sudo setcap cap_net_raw+ep "$BINARY_PATH"' some/network-tool
```

### `generate-password`
Generates a random password of a given length using `openssl` for randomness, optionally enforcing minimum counts of lowercase, uppercase, digit, and special characters.

**Usage:** `generate-password [OPTIONS]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Print the help message and exit. |
| `-l, --length LENGTH` | Length of the password to generate (default: 12). |
| `-L, --lower COUNT` | Require at least COUNT lowercase letters. |
| `-U, --upper COUNT` | Require at least COUNT uppercase letters. |
| `-d, --digits COUNT` | Require at least COUNT digits. |
| `-s, --special COUNT` | Require at least COUNT special characters. |

**Examples:**
```bash
generate-password
generate-password --length 20
generate-password -l 16 -d 2 -s 2
```

### `retry`
Repeatedly runs a command until it succeeds (exit 0) or is interrupted (exit 130), with a configurable delay between attempts and an optional cap on the number of retries.

**Usage:** `retry [-r retries] [-d delay] '<command>'`

| Argument / Flag | Description |
|---|---|
| `-r <retries>` | Maximum number of retries (numeric); default unlimited (`-1`). |
| `-d <delay>` | Delay in seconds between attempts (numeric); defaults to 1. |
| `'<command>'` | The command to run (executed via `bash -c`). |

**Examples:**
```bash
retry 'curl -sf https://example.com/health'
retry -r 5 -d 3 'ping -c1 host'
retry -d 10 'make deploy'
```

### `whichis`
Prints information about a command, bash function, or alias, including its resolved path and symlink chain, file type, owning package, and (optionally truncated) source content.

**Usage:** `whichis [-l <#> | -L] COMMAND`

| Argument / Flag | Description |
|---|---|
| `COMMAND` | The command, function, or alias to inspect. |
| `-l, --lines <#>` | Number of content lines to print (default 10). |
| `-L, --all-lines` | Print all content lines. |
| `-h, --help` | Print the help message and exit. |
| `--bash-completion` | Output shell-completion candidates (flags plus commands, functions, and aliases). |

**Examples:**
```bash
whichis ls
whichis -L my-function
whichis --lines 20 grep
```

### `lastcmd`
Prints the most recent command from shell history, excluding invocations of `lastcmd`/`lcmd` themselves and omitting the timestamp.

**Usage:** `lastcmd`

Takes no arguments.

**Examples:**
```bash
lastcmd
```

### `history_append`
Reads data from stdin and appends it to the shell history file, optionally prefixing a Unix epoch timestamp line.

**Usage:** `history_append [-h|--help] [-f|--file <file>] [-t|--with-timestamp]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Print the help message and exit. |
| `-f, --file <file>` | History file to write to; defaults to `$HISTFILE` or `~/.bash_history`. |
| `-t, --with-timestamp` | Include a timestamp line; defaults to whether `$HISTTIMEFORMAT` is set. |

**Examples:**
```bash
echo "make deploy" | history_append
echo "make deploy" | history_append -t -f ~/project.history
```

### `history_read`
Reads the shell history file referenced by `$HISTFILE`, pairing each command with a formatted ISO timestamp, with options to tail a number of lines, omit timestamps, or exclude commands by regex.

**Usage:** `history_read [-l LINES] [--no-timestamp] [-e PATTERN ...]`

| Argument / Flag | Description |
|---|---|
| `-l, --lines LINES` | Return only the last LINES history entries. |
| `--no-timestamp` | Print only the command lines, without timestamps. |
| `-e, --exclude PATTERN` | Exclude commands matching the given regex; repeatable. |

**Examples:**
```bash
history_read
history_read --lines 50 --no-timestamp
history_read -e '^ls' -e '^cd'
```

### `patch-apply`
Applies a unified diff with `patch -u -p0`, optionally stripping leading slashes from absolute paths in the patch header and optionally forcing every hunk onto a single target file.

**Usage:** `patch-apply [-h|--help] [--no-fix-paths] [-s|--single-file] [<file>]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show usage and exit. |
| `--no-fix-paths` | Do not rewrite absolute (`/`-prefixed) paths in the `---`/`+++` header lines to relative ones. |
| `-s, --single-file` | Force all hunks to apply to the first path seen in the patch. |
| `<file>` | The patch file to apply; if omitted, read from stdin. |

**Examples:**
```bash
patch-apply changes.diff
git diff | patch-apply --no-fix-paths
patch-apply --single-file - < my.patch
```

### `reminder`
An interactive terminal tool for managing Markdown reminders stored in `~/.cache/reminder`, with a two-pane edit UI (titles plus a `glow`-rendered preview), staged edits/adds/done-toggles that are only written on save, persistent custom ordering, and an open/done view split (completed reminders are renamed rather than deleted).

**Usage:** `reminder [OPTIONS]`

| Argument / Flag | Description |
|---|---|
| `--print` | Render all active reminders with `glow` and exit. |
| `--add` | Open an editor to compose a single new reminder, save it, and exit. |
| `-h, --help` | Show the help message and exit. |

Default edit-mode keybindings: `↑`/`↓` (or `k`/`j`) move between reminders; `tab` switches open/done views; `shift+↑`/`shift+↓` scroll the preview; `space` toggles done; `o` enters reorder mode (open view); `e` edits in vim; `n` adds a new reminder; `enter` saves all staged changes; `esc` backs out / aborts (prompting to discard if anything is staged).

**Examples:**
```bash
reminder
reminder --print
reminder --add
```

---

## Interactive Input Prompts

### `prompt`
Reads input from the terminal in one of four modes: multi-line (collecting lines until Ctrl-D), single-line, list selection (`--select`), or single-line input with completion (`--complete`), with optional custom prompt text, masked secret entry, and a default value; behavior also changes depending on the name it is invoked under (see aliases below).

**Usage:** `prompt [--prompt PROMPT] [--prompt-char CHAR] [--single-line] [--protected] [--default VALUE] [--select|--complete] [--delimiter DELIM|--delimiter-regex REGEX|--key-regex REGEX] [--return key|title|index|number] [--show-keys] [--header-lines N] [--no-header-uppercase] [--ignore-case] [--substring] [--files|--dirs] [--prefill TEXT] [--height N] [--no-color] [items or candidates ...]`

| Argument / Flag | Description |
|---|---|
| `-p, --prompt <text>` | Custom prompt text; defaults to `(Press Ctrl-D when done)` (multi-line), `Enter input:` (single-line, completion mode) or `Choose:` (select mode, and nothing at all when `--header-lines` is given). An empty value (`-p ''`) shows no prompt in any mode. |
| `--files` | Completion mode only: complete against file and directory names instead of a candidate list. Completing a directory appends a slash, so the next completion descends into it; hidden entries appear once a dot is typed. |
| `--dirs` | Like `--files`, but offers directories only. |
| `-c, --prompt-char <char>` | Custom prompt character; defaults to `> ` (multi-line), empty (single-line, completion mode) or `❯` (the pointer in select mode). |
| `-s, --single-line` | Read a single line (no prompt character shown). On a terminal this is an editable line: the cursor keys, Home/End, Backspace, Delete and Ctrl-A/E/U/K/W all work, while `↑`/`↓`, Tab and Esc do nothing. |
| `-P, --protected` | Prompt for a secret (input masked via `getpass`). |
| `-d, --default <value>` | Default value used when the user enters nothing (or clears the input again); in select mode the key, title or number of the entry the cursor starts on. In single-line mode, multi-line mode and the `--files`/`--dirs` modes it is pre-filled into the input, so Enter (or Ctrl-D) accepts it while it stays editable, and the `(default)` hint is then dropped as redundant. Cannot be combined with `--protected`. |
| `-l, --select` | Select one entry from a colored list; prints the selected item's key (see `--return`). |
| `-a, --complete` | Read a single line with Tab-completion against the given candidates. |
| `--delimiter <delim>` | Select mode only: splits each item into `<key><delim><title>` (default `=`); escape sequences like `\t` are honored, an empty value disables key parsing. |
| `--delimiter-regex <regex>` | Select mode only: like `--delimiter`, but the split point is the first (non-empty) match of this regular expression, e.g. `\s{2,}` for "at least two spaces"; the matched text itself is dropped. |
| `--key-regex <regex>` | Select mode only: takes the key from the first match of this regular expression (capture group 1 when the pattern has one) and keeps the whole item as the title, e.g. `^\S+` to display a full table row but return its first column. Mutually exclusive with `--delimiter` and `--delimiter-regex`. |
| `--return key\|title\|index\|number` | Select mode only: print the item's key (default), its title, its 0-based index or its 1-based number. |
| `--show-keys` | Select mode only: show the item keys next to the titles. |
| `--header-lines <n>` | Select mode only: treat the first `n` input lines as a header (default `0`). They are printed above the list in the `COLOR_TABLE_HEADER` style, indented so their columns line up with the item titles, and are neither selectable nor numbered. Header lines go through the same key parsing as the items, so only their title part is shown. Header lines are upper-cased (see `--no-header-uppercase`). Since the header already labels the list, the default `Choose:` prompt is suppressed (pass `-p` to get one anyway). |
| `--no-header-uppercase` | Select mode only: print the `--header-lines` header as given instead of upper-casing it. |
| `--ignore-case` | Completion mode only: match candidates case-insensitively. |
| `--substring` | Completion mode only: match candidates anywhere instead of at the start (disables the inline suggestion). |
| `--prefill <text>` | Pre-filled, editable input text for single-line, completion and multi-line mode. Wins over `-d`, which then keeps its `(default)` hint and stays the fallback for an emptied input. Not valid with `--protected` or in select mode. |
| `--height <n>` | Maximum number of list rows shown at once; defaults to what fits the terminal. |
| `--no-color` | Disable colored output (also honored: `NO_COLOR`, `TERM=dumb`, non-terminal output). |
| `<items ...>` | Select/completion mode only: the list items or completion candidates. Lines piped on stdin are appended to them. |

All modes draw their prompt on stderr (select and completion mode fall back to `/dev/tty` when stderr is redirected) and print the result to stdout. Colors come from the same `COLOR_*` variables the [color-parse](#color-parse) family uses and are dropped automatically when the output is not a terminal, when `--no-color` is given, or when `NO_COLOR` is set or `TERM` is empty/`dumb`:

| Element | Variable |
|---|---|
| Question text, prompt character (`> `), pointer (`❯`) | `COLOR_TEXT_INFO` (bold) |
| Highlighted select mode row | `COLOR_TEXT_INFO` on `COLOR_SELECTION_BACKGROUND` |
| Typed input | never styled — plain terminal text |
| Instruction prompts, i.e. fully parenthesized ones like `(Press Ctrl-D when done)` | `COLOR_TEXT_FADED` |
| `[y/N]` style options and the trailing colon, `(default)` hint, key hints, inline completion suggestion | `COLOR_TEXT_FADED` |
| The default choice inside `[y/N]` (the upper-case one) | `COLOR_TEXT_DEFAULT` |
| Select mode items, the selected item echoed after Enter | `COLOR_TEXT_DEFAULT`, `COLOR_TEXT_SUCCESS` |
| Item numbers, item keys | `COLOR_TEXT_NUMERIC`, `COLOR_TEXT_MUTED` |
| `--header-lines` header | `COLOR_TABLE_HEADER` |
| Quoted spans in the question text, e.g. the branch name in `Create branch "chore/bump-deps"?` | `COLOR_TEXT_CODE` (`203` on `236`, i.e. how [glow](https://github.com/charmbracelet/glow) renders `` `code` ``) |

Spans wrapped in `"`, `'` or `` ` `` are drawn as inline code snippets: the quotes become the padding of the highlighted block, so the prompt keeps its width. The quote has to open after a space or an opening bracket and close before a space or punctuation, so an apostrophe in `the user's file` is left alone.

Select and completion mode exit with status 1 when aborted with Esc and 130 on Ctrl-C.

#### Single-line mode keys (`--single-line` / `prompt-input` and the confirmation aliases)
On a terminal the line is edited in place, so a pre-filled `-d`/`--prefill` value can be changed instead of only accepted or retyped. Piped input and `--protected` use a plain read instead.

| Key | Action |
|---|---|
| `←` / `→`, Home / End, Ctrl-A / Ctrl-E | Move within the line. |
| Backspace / Delete | Delete before / under the cursor. |
| Ctrl-U / Ctrl-K / Ctrl-W | Kill to start of line / to end of line / the previous word. |
| Enter | Submit; an empty line returns `-d` when one was given. |
| `↑` / `↓`, Tab, Esc | Ignored. |
| Ctrl-D | Abort on an empty line (exit 1). |
| Ctrl-C | Abort (exit 130). |

#### Multi-line mode keys (`prompt` / `prompt-multiline`)
On a terminal, multi-line mode is a small editor: the text is redrawn in place, so the cursor can be moved freely through everything typed so far. `-d`/`--prefill` seed the buffer with editable text (newlines included), and an emptied buffer falls back to `-d`. Piped input and `--protected` keep using the plain line reader instead, so `printf 'a\nb\n' | prompt` behaves as before.

| Key | Action |
|---|---|
| `←` / `→` | Move by one character, wrapping into the previous/next line. |
| `↑` / `↓` | Move between lines, keeping the column you started from even across shorter lines. |
| PageUp / PageDown | Move by one screen. |
| Home / End, Ctrl-A / Ctrl-E | Jump to start / end of the current line. |
| Backspace | Delete before the cursor; at column 0 it joins the line to the previous one. |
| Delete | Delete under the cursor; at the end of a line it pulls the next line up. |
| Enter | Split the line at the cursor. |
| Tab | Insert a literal tab (drawn four columns wide). |
| Ctrl-U / Ctrl-K / Ctrl-W | Kill to start of line / to end of line / the previous word. |
| Ctrl-D | Finish and print the text. |
| Ctrl-C | Abort (exit 130). |

Lines longer than the terminal scroll sideways instead of wrapping (the off-screen part is marked with `…`), and when the text outgrows the screen the visible window follows the cursor and a faded `line/total` counter is shown.

Pasting works as expected: a pasted `\r\n` counts as one line break rather than two (so blank lines inside pasted text stay single), tabs are kept, and while a paste is still arriving the redraw is held back until the burst is through, so large pastes neither flicker nor slow down.

#### Select mode keys (`--select` / `prompt-select`)

| Key | Action |
|---|---|
| `↑` / `↓`, `k` / `j`, Ctrl-P / Ctrl-N | Move the cursor (wraps around). |
| PageUp / PageDown | Move by one screen. |
| Home / `g`, End / `G` | Jump to the first / last entry. |
| `1`…`9`, `0` | Jump to that entry (`0` is the tenth). |
| Enter | Select the highlighted entry and print it. |
| Esc, `q` | Abort (exit 1). |
| Ctrl-C | Abort (exit 130). |

#### Completion mode keys (`--complete` / `prompt-complete`)

| Key | Action |
|---|---|
| Tab | Complete as far as all matches agree; when that is ambiguous, open the candidate menu, then cycle forward through it. |
| Shift-Tab | Cycle backwards through the menu. |
| `↑` / `↓` | Open the menu (at the last / first candidate) and move through it; the input line always shows the highlighted candidate. |
| `→` at end of line | Accept the greyed-out inline suggestion. |
| Enter | Submit the current line (the highlighted candidate when the menu is open). |
| Esc | Close the menu and restore what was typed; with no menu open, abort (exit 1). |
| `←` / `→`, Home / End, Ctrl-A / Ctrl-E, Backspace, Delete, Ctrl-U, Ctrl-K, Ctrl-W | Standard line editing. |
| Ctrl-C | Abort (exit 130). |

**Examples:**
```bash
prompt --single-line --prompt "Your name:"
prompt --protected --single-line --prompt "Password:"
echo | prompt --single-line --default "fallback"
prompt --select --prompt "Pick a service:" api worker db
prompt --complete --prompt "Branch:" main develop staging
```

#### Symlink aliases (all point to `prompt`)
The script branches on its invoked name (`argv[0]`):

| Alias | Behavior |
|---|---|
| `prompt-continue` | Confirmation `Continue [y/N]:` (or custom text); exit 0 only on `y`/`Y`, else 1. |
| `prompt-continue-yes` | Confirmation `Continue [Y/n]:`; exit 0 on `y`/`Y` or empty (defaults to yes), else 1. |
| `prompt-yes-no` | Confirmation; trailing args + ` [Y/n]:` (default `Do it? [Y/n]:`); exit 0 on yes/empty, else 1. |
| `prompt-no-yes` | Confirmation; trailing args + ` [y/N]:` (default `Do it? [y/N]:`); exit 0 only on `y`/`Y`, else 1. |
| `prompt-input` | Single-line input; prints the entered value; trailing args become the prompt text. |
| `prompt-multiline` | Multi-line input (until Ctrl-D), printing all lines; trailing args become the prompt text. |
| `prompt-password` | Single-line masked secret entry (prompt `Password:`), printing the entered value. |
| `prompt-select` | Implies `--select`; trailing args are the list items (not the prompt text, use `-p` for that). |
| `prompt-complete` | Implies `--complete`; trailing args are the completion candidates (not the prompt text, use `-p` for that). |
| `prompt-file` | Implies `--complete --files` with prompt `Enter file:`, pre-filled with the current directory; trailing args become the prompt text. |
| `prompt-folder` | Implies `--complete --dirs` with prompt `Enter directory:`, pre-filled with the current directory; trailing args become the prompt text. |

**Examples:**
```bash
prompt-continue "Delete everything?" && rm -rf ./build
prompt-yes-no "Proceed with deploy" && deploy
name="$(prompt-input "What is your name?")"
secret="$(prompt-password)"
service="$(prompt-select -p "Pick a service:" "api=Public API gateway" "worker=Background worker")"
number="$(prompt-select --return number apple banana cherry)"
kubectl get pods -o name | prompt-select -p "Pod:" --delimiter ''
kubectl get pods | prompt-select -p "Pod:" --delimiter '' --header-lines 1
id="$(docker ps | prompt-select -p "Container:" --key-regex '^\S+' --header-lines 1)"
sha="$(git log --oneline -20 | prompt-select -p "Commit:" --delimiter-regex '\s+')"
branch="$(git branch --format '%(refname:short)' | prompt-complete -p "Branch:")"
host="$(prompt-complete --ignore-case -p "Host:" web-01 web-02 db-01)"
config="$(prompt-file "Config to edit:" --prefill "${HOME}/.config/")"
```

### `prompt-command`
Prompts the user for a shell command using readline, with custom Tab-completion that completes against available commands; an optional default can be accepted by pressing Enter.

**Usage:** `prompt-command [-d|--default <command>]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the help message and exit. |
| `-d, --default <command>` | Default command; press Enter at the prompt to use it. |

**Examples:**
```bash
prompt-command
cmd="$(prompt-command --default 'git status')"
```

### `prompt-file`
Symlink to [prompt](#prompt) implying `--complete --files`: prompts for a file path with path completion (Tab completes the current component, completing a directory descends into it), pre-filled with the current working directory, and prints the chosen path.

**Usage:** `prompt-file [<prompt text ...>] [-d|--default PATH] [--prefill PATH] [--height N]`

| Argument / Flag | Description |
|---|---|
| `<prompt text ...>` | Custom prompt text; defaults to `Enter file:`. |
| `-d, --default <path>` | Default path: it is pre-filled into the input line (so Enter accepts it, and it stays editable and completable) and is also used when the line is cleared. |
| `--prefill <path>` | Start from this path instead of the current working directory or the default. |
| `--height <n>` | Maximum number of candidate rows shown at once. |

**Examples:**
```bash
file="$(prompt-file)"
file="$(prompt-file "Config to edit:" --prefill "${HOME}/.config/")"
file="$(prompt-file -d "${HOME}/.bashrc")"
```

### `prompt-folder`
Symlink to [prompt](#prompt) implying `--complete --dirs`: same as `prompt-file`, but only directories are offered.

**Usage:** `prompt-folder [<prompt text ...>] [-d|--default PATH] [--prefill PATH] [--height N]`

| Argument / Flag | Description |
|---|---|
| `<prompt text ...>` | Custom prompt text; defaults to `Enter directory:`. |
| `-d, --default <path>` | Default path: it is pre-filled into the input line (so Enter accepts it, and it stays editable and completable) and is also used when the line is cleared. |
| `--prefill <path>` | Start from this path instead of the current working directory or the default. |
| `--height <n>` | Maximum number of candidate rows shown at once. |

**Examples:**
```bash
dir="$(prompt-folder)"
dir="$(prompt-folder "Where to install:" --prefill /usr/local/)"
dir="$(prompt-folder -d "${HOME}/Downloads")"
```

### `choose`
Thin wrapper around [prompt](#prompt)'s select mode for callers that pass their items as one newline separated string: shows the colored, arrow-key navigable list on stderr and prints the chosen item to stdout. Exits 1 when aborted with Esc and 130 on Ctrl-C.

**Usage:** `choose [-p|--prompt <prompt>] [-n|--newlines] <list of choices>`

| Argument / Flag | Description |
|---|---|
| `-p, --prompt <prompt>` | Custom prompt text shown above the list (default: "Choose from list"). |
| `-n, --newlines` | Print a blank line before and after the menu. |
| `<list of choices>` | One or more positional arguments, each a selectable menu item; arguments containing newlines are split into one item per line. |

**Examples:**
```bash
choose apple banana cherry
selected="$(choose -p "Pick a branch" -n main develop staging)"
```

### `readkey`
Reads a single keystroke from the terminal and prints a human-readable name for it, decoding escape sequences for arrow, navigation, and editing keys as well as space, enter, backspace, and escape.

**Usage:** `readkey`

Takes no arguments.

**Examples:**
```bash
readkey
key="$(readkey | tail -n1)"
```

### `fzf-with-header`
A wrapper around `fzf` that treats the first input line as a fixed header, with support for column selection, periodic command reloads, and dispatching the selection to a key command. The mapped keys (built-in bindings plus any `--bind`/`--expect` keys passed after `--`) are displayed at the top, wrapped to the terminal width; for `execute`/`become` bindings the bound command is shown, otherwise the fzf action name. The key list shrinks on short terminals so the list keeps at least three rows: it is packed into fewer lines with the keys that no longer fit dropped behind a `…`, and once not even one line is left it is hidden completely.

Whenever a preview window is configured, `shift-left`/`shift-right` turn its line wrapping on and off and `ctrl-p` hides and shows the preview pane; both are listed in the key list. The `ctrl-p` binding is skipped when the caller uses that key itself, be it through `--bind`/`--expect` or one of the keys handled inside `fzf`.

**Usage:** `fzf-with-header [--command <command>] [--key-command <command>] [--key-descriptions <key>:<description>,...] [--reload-keys <key>,...] [--exec-reload-keys <key>,...] [--silent-keys <key>,...] [--exec-keys <key>,...] [--watch <seconds>] [--watch-delay <seconds>] [--watch-while <command>] [--columns <cols>] [--filter-columns <cols>] [--delimiter <delimiter>] [<query ...>] -- [fzf args]`

An `--expect` key ends `fzf`, so its key command runs with the picker gone and the picker is started again afterwards - the screen is torn down and rebuilt on every such key press. The four key options below handle a key inside the running `fzf` instead. They take the same key command: it is handed the payload an `--expect` exit would have produced, the key on the first line and the selected line on the second, so a key moves from `--expect` to one of them without the key command changing. Its exit code is ignored, and a key cannot be listed twice.

They differ in two things: whether the key command gets the terminal handed over, and whether the list is reloaded afterwards. A key command that keeps the screen must not write to stdout, since that is the command substitution around `fzf`; whatever it writes to stderr is shown in red above the header, wrapped to the list width, until the next key press. A key command that gets the terminal handed over draws on the screen itself, stdout included, and is on its own for showing what it did. A reload replaces the list with `reload-sync` and puts the cursor back on the first entry, so the view ends up where a restart of `fzf` would have left it - unless the caller positions the cursor on the `load` event itself, which `fzf` fires again after every reload. Keys that have to end the picker, because they return something on stdout or because another picker takes over, stay in `--expect`.

| Argument / Flag | Description |
|---|---|
| `--command <command>` | Command whose output is piped into `fzf`; enables `--print-query` and is required for `--watch`. Binds `ctrl-r` to reload the output on demand (skipped if `ctrl-r` is already bound or described by the caller). |
| `--key-command <command>` | Command invoked with the selected result; exit 1 quits with success, 255 quits with failure, anything else loops again. |
| `--key-descriptions <key>:<description>,...` | When given, only these keys are shown at the top, with these descriptions and in this order (inferred keys are suppressed). Useful for `--expect` keys, whose effect lives in the `--key-command`. |
| `--reload-keys <key>,...` | Keys that run the `--key-command` inside the running `fzf` and reload the list afterwards, instead of ending `fzf` and starting it again (requires `--command` and `--key-command`). For a key that changes what the list shows without needing the screen. |
| `--exec-reload-keys <key>,...` | Like `--reload-keys`, but the key command gets the terminal handed over, for a pager, an editor or a prompt (requires `--command` and `--key-command`). |
| `--silent-keys <key>,...` | Like `--reload-keys` without the reload, for a key that leaves the list as it is (requires `--key-command`). |
| `--exec-keys <key>,...` | Like `--exec-reload-keys` without the reload (requires `--key-command`). |
| `--watch <seconds>` | Reload command output every `n` seconds (non-negative integer; requires `--command`). A leading `↻ <n>s` indicator in the key list names the current reload interval (the delay until the first reload, then the interval); `ctrl-r` restarts the interval. |
| `--watch-delay <seconds>` | Delay before the first reload (default: 2). |
| `--watch-while <command>` | Keep reloading only while this command exits successfully; it is checked after each reload interval, so the first reload always happens. Lets a view stop refreshing once whatever it watches reached a final state (requires `--watch`). The indicator switches to `↻ off` once reloading stopped; a manual `ctrl-r` refresh puts the watching back on its interval (indicator back to `↻ <n>s`), so if the reload of that refresh brought the watched state back the reloading continues, otherwise it stops again after one interval. |
| `--columns <cols>` | Comma-separated columns to display (passed to `fzf --with-nth`). |
| `--filter-columns <cols>` | Comma-separated columns to match against (passed to `fzf --nth`). |
| `--delimiter <delimiter>` | Field delimiter for `fzf` (default: two-or-more spaces). |
| `--help` | Show usage and exit. |
| `<query ...>` | Initial query terms pre-filled into `fzf`. |
| `-- [fzf args]` | Everything after `--` is passed straight through to `fzf`. |

**Examples:**
```bash
fzf-with-header --command "ps aux" --watch 5
fzf-with-header --command "list-builds" --watch 5 --watch-delay 3 --watch-while "has-running-builds"
fzf-with-header --command "cat data.tsv" --columns 1,3 --delimiter $'\t'
fzf-with-header docker -- --height=40%
fzf-with-header --key-command handle-key --key-descriptions "ctrl-x:delete entry,ctrl-r:refresh" -- --expect=ctrl-x,ctrl-r
fzf-with-header --command "list-items" --key-command handle-key --reload-keys "alt-d,alt-r" --exec-keys "ctrl-d" --silent-keys "ctrl-o" --key-descriptions "alt-d:delete,alt-r:reset,ctrl-d:diff,ctrl-o:open,enter:pick" -- --expect=enter
```

---

## SSH, Network and System

### `ssh`
Wrapper around `/usr/bin/ssh` that records the command in shell history (skipping `git@`, `js01`, and `-G` invocations) before executing the real SSH client.

**Usage:** `ssh [ssh arguments]`

| Argument / Flag | Description |
|---|---|
| `[ssh arguments]` | All arguments are passed through to the underlying `ssh` command. |

**Examples:**
```bash
ssh user@example.com
ssh -p 2222 user@host
```

### `sshr`
Re-adds an SSH host's key to `known_hosts` (resolving its real hostname via `ssh -G`) and then connects, taking the SSH command from arguments or the most recent `ssh` line in bash history.

**Usage:** `sshr [--prompt] [ssh arguments]`

| Argument / Flag | Description |
|---|---|
| `--prompt` | Ask for confirmation before re-adding the host to `known_hosts`. |
| `[ssh arguments]` | The SSH command/arguments; if omitted, the last `ssh` command from history is used. |

**Examples:**
```bash
sshr user@example.com
sshr --prompt user@host
sshr
```

### `ssh-httpd-tunnel`
Starts a local Python HTTP server on a generated port and opens a reverse SSH tunnel so the remote host can reach it on the same port.

**Usage:** `ssh-httpd-tunnel [ssh arguments]`

| Argument / Flag | Description |
|---|---|
| `[ssh arguments]` | Arguments (typically the destination host) passed through to `ssh` for the reverse tunnel. |

**Examples:**
```bash
ssh-httpd-tunnel user@remote-host
```

### `ssh-terminal`
Opens a new Terminator window that SSHes into the given host, falling back to `sshr` (re-add known host) if the connection fails, and drops into a login shell afterward.

**Usage:** `ssh-terminal [ssh arguments]`

| Argument / Flag | Description |
|---|---|
| `[ssh arguments]` | Arguments (typically the destination host) passed to the SSH connection. |

**Examples:**
```bash
ssh-terminal user@example.com
```

### `terminal-session`
Opens an SSH session to the local host as the current user and dumps the interactive login shell's declared variables (`declare -p`).

**Usage:** `terminal-session`

Takes no arguments.

**Examples:**
```bash
terminal-session
```

### `screener`
Interactive menu for listing, resuming, force-detaching, or creating GNU `screen` sessions, built on [prompt](#prompt)'s select mode (arrow keys, Esc cancels).

**Usage:** `screener`

Takes no arguments.

**Examples:**
```bash
screener
```

### `vpn-up`
Brings a NetworkManager VPN connection up or down by name, reading a VPN password from stdin when one is piped in.

**Usage:** `vpn-up <vpn-name> [-d|--down]`

| Argument / Flag | Description |
|---|---|
| `<vpn-name>` | Name of the VPN connection to act on. |
| `-d, --down` | Bring the VPN connection down instead of up. |

**Examples:**
```bash
vpn-up work
vpn-up work --down
echo 'mypassword' | vpn-up work
```

### `wifi`
Manages Wi-Fi connections via NetworkManager using friendly names mapped to SSIDs, supporting auto-selection, reconnect, disconnect, kernel-module reload, and various listing options.

**Usage:** `wifi [OPTIONS] NAME`

| Argument / Flag | Description |
|---|---|
| `NAME` | Connection to connect to: one of `mobile`, `work`, `home`, or `auto`. With no arguments, prints the current connection's mapped name. |
| `-m, --map SSID` | Print the friendly name mapped to the given SSID. |
| `-r, --reconnect` | Force a reconnect by toggling the radio off and back on. |
| `-k, --reload-module` | Reload the wireless kernel module. |
| `-d, --disconnect` | Toggle the radio off and on (disconnect). |
| `-f, --force` | Force reconnect even if already connected to the target SSID. |
| `--list-available-ssids` | List currently available SSIDs. |
| `--list-available-names` | List available SSIDs mapped to their friendly names. |
| `--print-names` | Print all possible names (including `auto`). |
| `-h, --help` | Show the help message and exit. |

**Examples:**
```bash
wifi
wifi work
wifi auto
wifi --force home
wifi --list-available-names
```

### `loggedin`
Reports the currently logged-in graphical-session user, optionally as a numeric UID, a UID/name pair, or the user's home directory.

**Usage:** `loggedin [-h|--help] [--id] [--id-name] [--home]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Show the usage message and exit. |
| `--id` | Output the user's numeric UID instead of the name. |
| `--id-name` | Output both the UID and the name (colon-separated). |
| `--home` | Output the user's home directory instead of the name. |

`--id`, `--id-name`, and `--home` are mutually exclusive; by default the username is printed.

**Examples:**
```bash
loggedin
loggedin --id
loggedin --home
```

### `updater`
Updates a selectable set of system packages, desktop applications, and CLI tools using their appropriate package managers, vendor repositories, install scripts, or Git releases. With no software arguments, it processes every supported type except entries explicitly disabled in the script.

**Usage:** `updater [OPTIONS] [SOFTWARE ...]`

| Argument / Flag | Description |
|---|---|
| `SOFTWARE` | One or more software types to update, or `all`; omit to process all supported types. |
| `-d, --dry-run` | Check for updates without installing them. |
| `-t, --types TYPES` | Deprecated comma-separated alternative to positional software types. |
| `--verbose` | Print commands and additional update details. |
| `-h, --help` | Show usage and the current list of supported software types. |
| `--bash-completion` | Output completion candidates (flags plus software types). |

The updater is intended for Debian/Ubuntu-style systems and uses `loggedin` to preserve the graphical-session user while elevating individual system operations with `sudo`. Update methods have tool-specific dependencies such as `apt`, `flatpak`, `npm`, `curl`, `jq`, and `install-git-release`.

**Examples:**
```bash
updater --dry-run apt flatpak
updater codex claude
updater --verbose all
make update UPDATE_ARGS='--dry-run apt'
```

### `bluetooth-trigger`
Listens on the system D-Bus for BlueZ Bluetooth device add/remove events and prints the device object path as each device appears or disappears (with commented-out scaffolding for triggering actions on a specific MAC address).

**Usage:** `bluetooth-trigger`

Takes no arguments.

**Examples:**
```bash
bluetooth-trigger
```

### `power-log`
Prints log entries from the `power-trigger.service` user systemd unit for the last 72 hours, piped into `less`, defaulting to just lid open/close events.

**Usage:** `power-log [OPTIONS]`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Print the help message and exit. |
| `-a, --all` | Print all log entries, not just lid open/close events. |

**Examples:**
```bash
power-log
power-log --all
```

### `power-trigger`
A long-running D-Bus service daemon that watches UPower lid and battery state plus logind sleep signals, and automatically locks the screen on lid close and suspends the laptop (after unmounting CIFS shares) when the lid stays closed on battery; meant to be run as a systemd user service.

**Usage:** `power-trigger`

Takes no arguments.

**Examples:**
```bash
power-trigger
systemctl --user start power-trigger.service
```

### `set-slack-profile`
Sets your Slack status via a webhook, either automatically based on the current network connection (Wi-Fi SSID or Ethernet domain) or by a manual override, with optional time-limited persistence.

**Usage:** `set-slack-profile [-s STATUS [DAYS]] [-l] [-r]`

| Argument / Flag | Description |
|---|---|
| `-s, --status STATUS [DAYS]` | Manually set the given status, overriding auto-detection. Optional `DAYS` auto-resets the override after N days (persistable statuses only). |
| `-l, --list` | List the available statuses (`InTransit`, `OnVacation`, `HomeOffice`, `AtWork`) and exit. |
| `-r, --reset` | Reset (remove) the persisted manual override. |

**Examples:**
```bash
set-slack-profile
set-slack-profile --list
set-slack-profile --status OnVacation 5
set-slack-profile --reset
```

### `remapkeys`
Applies an X11 keyboard remap: sets the German layout, enables mouse keys, and maps keycode 135 to the right mouse button; refuses to run on Wayland (pointing the user to GNOME Settings and `ydotool` instead).

**Usage:** `remapkeys`

Takes no arguments.

**Examples:**
```bash
remapkeys
```

### `launcher`
Opens a Terminator-based quick-launch terminal window that auto-closes after a few idle seconds, refocusing the existing window instead of spawning a new one if already running.

**Usage:** `launcher`

Takes no arguments.

**Examples:**
```bash
launcher
```

### `cron-to-ical`
Generates an iCalendar (`.ics`) feed on stdout containing an event for each occurrence of a cron expression over a date range, converting times to UTC.

**Usage:** `cron-to-ical <cron> [--duration <duration>] [--start_date YYYY-MM-DD] [--end_date YYYY-MM-DD]`

| Argument / Flag | Description |
|---|---|
| `<cron>` | The cron expression to expand into calendar events (required). |
| `--duration <duration>` | Event length, e.g. `"1d 2h 3m 4s"` or a bare number of seconds. Default: `1d`. |
| `--start_date <date>` | First date to generate events from (`YYYY-MM-DD`). Default: today. |
| `--end_date <date>` | Last date to generate events through (`YYYY-MM-DD`). Default: 50 years from start. |

**Examples:**
```bash
cron-to-ical "0 9 * * 1-5" > workdays.ics
cron-to-ical "30 8 * * *" --duration "1h 30m" --end_date 2026-12-31
cron-to-ical "0 0 1 * *" --start_date 2026-01-01 --duration 3600
```

---

## Window and Display Management

These tools work on both X11 (via `xdotool`/`wmctrl`/`xrandr`) and Wayland/GNOME (via the bundled `cli-helpers-window-bridge` GNOME Shell extension installed by `make install`).

### `window-active`
Prints the window ID of the currently focused (active) window, on both Wayland and X11.

**Usage:** `window-active`

Takes no arguments.

**Examples:**
```bash
window-active
```

### `window-by-class`
Prints the IDs of all windows whose WM class (or sandboxed app ID on Wayland) matches one of the given class names.

**Usage:** `window-by-class <classes ...>`

| Argument / Flag | Description |
|---|---|
| `classes ...` | One or more WM class names to match against open windows. |

**Examples:**
```bash
window-by-class firefox
window-by-class org.gnome.Console code
```

### `window-by-title`
Prints the IDs of all windows whose title exactly matches the given string.

**Usage:** `window-by-title <title>`

| Argument / Flag | Description |
|---|---|
| `title` | The exact window title to match. |

**Examples:**
```bash
window-by-title "Inbox - Mozilla Thunderbird"
```

### `window-focus`
Focuses (activates and raises) the window with the given ID, on both Wayland and X11.

**Usage:** `window-focus <id>`

| Argument / Flag | Description |
|---|---|
| `id` | The ID of the window to focus. |

**Examples:**
```bash
window-focus 0x03400007
window-focus "$(window-by-class firefox | head -n 1)"
```

### `window-focus-by-class`
Cycles focus through all windows matching the given WM class(es); if one is already active it focuses the next one in sorted order, otherwise the first match, optionally waiting for a matching window to appear.

**Usage:** `window-focus-by-class [--wait <seconds>] <classes ...>`

| Argument / Flag | Description |
|---|---|
| `--wait <seconds>` | Retry once per second for up to this many seconds until a matching window appears. |
| `classes ...` | One or more WM class names to match against open windows. |

**Examples:**
```bash
window-focus-by-class firefox
window-focus-by-class --wait 5 org.gnome.Console
```

### `window-focus-by-title`
Cycles focus through all windows matching the given title; if one is already active it focuses the next one, otherwise the first match, optionally waiting for a matching window to appear.

**Usage:** `window-focus-by-title [--wait <seconds>] <title>`

| Argument / Flag | Description |
|---|---|
| `--wait <seconds>` | Retry once per second for up to this many seconds until a matching window appears. |
| `title` | The window title to match. |

**Examples:**
```bash
window-focus-by-title "Inbox - Mozilla Thunderbird"
window-focus-by-title --wait 10 "Calculator"
```

### `window-launch-or-focus-by-class`
Focuses an existing window matching the given WM class(es), or launches the named desktop application via `gtk-launch` if no such window exists.

**Usage:** `window-launch-or-focus-by-class <desktop> <classes ...> -- [<arguments...>]`

| Argument / Flag | Description |
|---|---|
| `desktop` | The desktop file (application) to launch if no matching window is found. |
| `classes ...` | One or more WM class names to look for before launching. |
| `-- [<arguments...>]` | Arguments after `--` are passed through to `gtk-launch`. |

**Examples:**
```bash
window-launch-or-focus-by-class firefox.desktop firefox --
window-launch-or-focus-by-class org.gnome.Console.desktop org.gnome.Console --
```

### `window-launch-or-focus-by-title`
Focuses an existing window matching the given title, or launches the named desktop application via `gtk-launch` if no such window exists.

**Usage:** `window-launch-or-focus-by-title <desktop> <title> [<arguments...>]`

| Argument / Flag | Description |
|---|---|
| `desktop` | The desktop file (application) to launch if no matching window is found. |
| `title` | The window title to look for before launching. |
| `arguments...` | Any further arguments are passed through to `gtk-launch`. |

**Examples:**
```bash
window-launch-or-focus-by-title org.gnome.Calculator.desktop "Calculator"
```

### `window-list`
Lists all open windows with their ID, workspace, host, WM class, and title, in a format compatible with `wmctrl -xl`, on both Wayland and X11.

**Usage:** `window-list`

Takes no arguments.

**Examples:**
```bash
window-list
window-list | grep -i firefox
```

### `window-send-key`
Sends one or more keystrokes (or types literal text) to the focused window using `ydotool` on Wayland or `xdotool` on X11.

**Usage:** `window-send-key [--type] <key> ...`

| Argument / Flag | Description |
|---|---|
| `--type` | Type the arguments as literal text instead of sending key combinations. |
| `key ...` | One or more keys/key combinations (or text, with `--type`) to send. |

**Examples:**
```bash
window-send-key ctrl+c
window-send-key Return
window-send-key --type "hello world"
```

### `window-shortcuts`
Lists GNOME keyboard shortcuts (including custom media-key shortcuts) as a colorized, space-separated table with key, bindings, and descriptions.

**Usage:** `window-shortcuts [--schema-regex REGEX] [--color [auto|always|never]] [--include-schema]`

| Argument / Flag | Description |
|---|---|
| `--schema-regex REGEX` | Regex filtering which gsettings schemas are shown (default: all). |
| `--color [auto\|always\|never]` | Colorize the output; `auto` colorizes only when writing to a terminal (default). |
| `--include-schema` | Include the SCHEMA column in the output. |

**Examples:**
```bash
window-shortcuts
window-shortcuts --include-schema
window-shortcuts --schema-regex 'wm.keybindings' --color always
```

### `window-screen-focused`
Finds the name of the relevant monitor, by default preferring the monitor of the active window, then the mouse cursor, then the primary monitor.

**Usage:** `window-screen-focused [--mouse | --primary | --window | --help]`

| Argument / Flag | Description |
|---|---|
| `--mouse` | Find the monitor where the mouse cursor is located. |
| `--primary` | Get the name of the primary monitor. |
| `--window` | Find the monitor containing the currently active window. |
| `--help` | Display the help message and exit. |

Only one mode flag at a time. With no flag, tries active window, then mouse, then primary.

**Examples:**
```bash
window-screen-focused
window-screen-focused --mouse
window-screen-focused --primary
```

### `window-screen-geometry`
Prints the geometry (width, height, x, y, and optionally scale) of a named display, accounting for the display scale unless told otherwise.

**Usage:** `window-screen-geometry [-h|--help] [--ignore-scale] [-r|--raw] <display>`

| Argument / Flag | Description |
|---|---|
| `-h, --help` | Display the help message and exit. |
| `--ignore-scale` | Do not apply the display scale factor to the geometry. |
| `-r, --raw` | Print the geometry as a single `WxH+X+Y` string instead of separate lines. |
| `display` | The name of the display/monitor to query (e.g. `DP-1`). |

**Examples:**
```bash
window-screen-geometry DP-1
window-screen-geometry --raw HDMI-1
window-screen-geometry --ignore-scale eDP-1
```

### `window-screen-list`
Lists all monitors, optionally limited to one display, printing names and optionally their geometry, or just the primary monitor.

**Usage:** `window-screen-list [-d|--display <name>] [-g|--geometry] [-p|--primary] [-h|--help]`

| Argument / Flag | Description |
|---|---|
| `-d, --display <name>` | Select a single display by name. |
| `-g, --geometry` | Print monitor geometry (`name x y w h`) instead of just names. |
| `-p, --primary` | Print only the primary monitor (cannot be combined with `--display`). |
| `-h, --help` | Display the help message and exit. |

**Examples:**
```bash
window-screen-list
window-screen-list --geometry
window-screen-list --primary
window-screen-list --display DP-1 --geometry
```

### `screen-color`
Interactive terminal tool for adjusting per-output display gamma (color) on X11 or Wayland/GNOME, with support for saving and loading named presets.

**Usage:** `screen-color [--list] [--load ALIAS] [--x11] [output]`

| Argument / Flag | Description |
|---|---|
| `--list` | List available display outputs and exit. |
| `--load ALIAS` | Load and apply a saved preset by alias (non-interactive), then exit. |
| `--x11` | Force X11 mode, using `xrandr` instead of the Wayland/GNOME DBus backend. |
| `output` | The display output to adjust (defaults to the first available output). |

Interactive keys: `q/a`, `w/s`, `e/d` raise/lower red, green, blue gamma; `TAB` cycles outputs; `r` resets to 1.0; `p` loads a preset; `P` saves a preset; `ESC` exits.

**Examples:**
```bash
screen-color --list
screen-color HDMI-1
screen-color --load night
```

### `xorwayland`
Prints whether the current desktop session is running under X11 (`x`) or Wayland (`wayland`), based on session environment variables.

**Usage:** `xorwayland`

Takes no arguments.

**Examples:**
```bash
xorwayland
if [ "$(xorwayland)" = "wayland" ]; then echo "on Wayland"; fi
```
