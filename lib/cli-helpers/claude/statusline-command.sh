#!/usr/bin/env bash
# Claude Code status line.
#   <title> <folder> <model (flags, context)> <5h> <Week>
#
# title  : grey «» brackets, brighter-grey text (not white). From session_name
#          (/rename) else latest {"type":"ai-title"} .aiTitle in transcript.
# folder : bold, theme default foreground (matches "printing code" look).
# model  : name in bold green; "(" ")" and "," in grey; each flag inside () in
#          orange. Flags: 1M context window, effort, ultracode, permission mode,
#          CAVEMAN, context-window %.
# 5h/Week: label white, ":" grey, value colored (green<50 / yellow>=50 /
#          red>=80 / bold-red>=90), "%" grey.
# Note: no "daily" rate-limit field exists — only 5h rolling + 7-day/weekly.

input=$(cat)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
e=$'\033'
GREY='38;5;245'      # punctuation: « » ( ) , : %
TITLECLR='38;5;253'  # title text — brighter than grey, not white
ORANGE='38;5;172'    # CAVEMAN flag (kept as-is)
NAMECLR='1;32'       # model name, bold green
FOLDERCLR='38;2;179;189;255' # folder — theme inline-code color (#b3bdff periwinkle)
CTXWINCLR='38;5;39'  # context window flag (1M / 200K) — blue
RMARGIN=5            # cols reserved at right edge (Claude clips ~5 below COLUMNS)
# ---- colors sampled from the Claude Code UI screenshots (truecolor) ----
ULTRAFG='38;2;255;255;255'  # ultracode badge text (white)
ULTRABG='48;2;140;80;240'   # ultracode badge background (#8c50f0 purple)
# effort-level colors (match the /effort picker):
EFF_low='38;2;255;193;7'    # #ffc107 gold
EFF_medium='38;2;78;186;101' # #4eba65 green
EFF_high='38;2;177;185;249'  # #b1b9f9 periwinkle
EFF_xhigh='38;2;175;135;255' # #af87ff violet
EFF_max='38;2;245;139;87'    # #f58b57 orange (gradient in UI, approximated)
# permission-mode colors (match the prompt indicator):
MODE_auto='38;2;255;193;7'   # #ffc107 gold
MODE_plan='38;2;72;150;140'  # #48968c teal
MODE_accept='38;2;175;135;255' # #af87ff violet
MODE_bypass='38;2;255;95;95' # red (dangerous mode)

# --- fields from stdin JSON (0x1f-delimited; non-whitespace keeps empties) ---
IFS=$'\037' read -r cwd model ctx five_h seven_d transcript session_name effort ctxsize < <(
  printf '%s' "$input" | jq -r '[
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (.context_window.used_percentage // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.transcript_path // ""),
    (.session_name // ""),
    (.effort.level // ""),
    (.context_window.context_window_size // "")
  ] | join("\u001f")'
)
[ -z "$effort" ] && effort="$CLAUDE_EFFORT"
model="${model% (*context)}"   # drop "(1M context)" — shown as a flag instead

# --- transcript-derived: title, permission mode, ultracode ---
title="$session_name"
perm=""
ultra=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  tail_json=$(tail -n 1200 "$transcript" 2>/dev/null)
  if [ -z "$title" ]; then
    title=$(printf '%s' "$tail_json" | jq -rc 'select(.type=="ai-title") | .aiTitle // empty' 2>/dev/null | tail -1)
  fi
  perm=$(printf '%s' "$tail_json" | jq -rc 'select(.type=="permission-mode") | .permissionMode // empty' 2>/dev/null | tail -1)
  # ultracode = latest "Set effort level to X" is "ultracode"
  last_effort=$(printf '%s' "$tail_json" | grep -o 'Set effort level to [a-z]*' 2>/dev/null | tail -1)
  [ "$last_effort" = "Set effort level to ultracode" ] && ultra="ultracode"
fi

# --- title (grey brackets, brighter-grey text) ---
seg_title=""
if [ -n "$title" ]; then
  [ "${#title}" -gt 50 ] && title="${title:0:49}…"
  seg_title="${e}[${GREY}m«${e}[${TITLECLR}m${title}${e}[${GREY}m»${e}[0m"
fi

# --- folder (theme inline-code color; $HOME -> ~) ---
case "$cwd" in
  "$HOME"/*) disp_cwd="~${cwd#"$HOME"}" ;;
  "$HOME")   disp_cwd="~" ;;
  *)         disp_cwd="$cwd" ;;
esac
seg_folder="${e}[${FOLDERCLR}m${disp_cwd}${e}[0m"

# --- caveman flag -> "CAVEMAN"/"CAVEMAN:MODE" (orange handled as a flag) ---
cmtext=""
FLAG="$CFG/.caveman-active"
if [ ! -L "$FLAG" ] && [ -f "$FLAG" ]; then
  MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  case "$MODE" in
    ""|full) cmtext="CAVEMAN" ;;
    off)     cmtext="" ;;
    lite|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
             cmtext="CAVEMAN:$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')" ;;
    *)       cmtext="" ;;
  esac
fi

effort_color() {
  case "$1" in
    low) echo "$EFF_low";; medium) echo "$EFF_medium";; high) echo "$EFF_high";;
    xhigh) echo "$EFF_xhigh";; max) echo "$EFF_max";; *) echo "$ORANGE";;
  esac
}
mode_color() {
  case "$1" in
    auto) echo "$MODE_auto";; plan) echo "$MODE_plan";;
    accept) echo "$MODE_accept";; bypass) echo "$MODE_bypass";; *) echo "$ORANGE";;
  esac
}

# --- model with flags/context in () — each flag carries its own color ---
flags=()
# context window — blue
case "$ctxsize" in
  1000000) flags+=("${e}[${CTXWINCLR}m1M${e}[0m") ;;
  200000)  flags+=("${e}[${CTXWINCLR}m200K${e}[0m") ;;
esac
# effort — per-level color
[ -n "$effort" ] && flags+=("${e}[$(effort_color "$effort")m${effort}${e}[0m")
# ultracode — fg-on-bg badge
[ -n "$ultra" ] && flags+=("${e}[${ULTRAFG};${ULTRABG}m ${ultra} ${e}[0m")
# permission mode — per-mode color from the UI
case "$perm" in
  ""|default|normal) m="" ;;
  acceptEdits)        m="accept" ;;
  bypassPermissions)  m="bypass" ;;
  *)                  m="$perm" ;;
esac
[ -n "$m" ] && flags+=("${e}[$(mode_color "$m")m${m}${e}[0m")
# caveman — orange
[ -n "$cmtext" ] && flags+=("${e}[${ORANGE}m${cmtext}${e}[0m")

seg_model=""
if [ -n "$model" ]; then
  seg_model="${e}[${NAMECLR}m${model}${e}[0m"
  if [ ${#flags[@]} -gt 0 ]; then
    inner=""
    for it in "${flags[@]}"; do
      [ -n "$inner" ] && inner="${inner}${e}[${GREY}m, ${e}[0m"
      inner="${inner}${it}"
    done
    seg_model="${seg_model} ${e}[${GREY}m(${e}[0m${inner}${e}[${GREY}m)${e}[0m"
  fi
fi

# --- usage bars (Session = 5h window, Week = 7-day) ---
# 20-char bar: white text " <label> ... <n>% " on a fill/track background.
# Fill width ∝ usage; fill bg colored by tier; remainder is a dark track.
WHITE='38;2;255;255;255'  # text on the (dark) track
DARKFG='38;2;40;42;64'    # text on the (light) fill
FILLBG='48;2;177;185;249' # progress fill (#b1b9f9 periwinkle, from Usage menu)
TRACKBG='48;2;80;83;112'  # track (#505370 slate)
usage_bar() {  # $1=value $2=label -> 20-char bar (empty if no value)
  # dark text on fill / white text on track; label bold, value regular.
  local v="$1" label="$2" n left right mid bartext fillN lablen
  [ -z "$v" ] && return
  n=${v%.*}; [ -z "$n" ] && n=0
  case "$n" in *[!0-9]*) return;; esac
  [ "$n" -gt 100 ] && n=100
  left=" ${label}"; right="${n}% "
  mid=$((20 - ${#left} - ${#right})); [ "$mid" -lt 1 ] && mid=1
  bartext="${left}$(printf '%*s' "$mid" '')${right}"
  bartext="${bartext:0:20}"                       # clamp to 20 cols
  fillN=$(( (n*20 + 50) / 100 ))                   # rounded filled cols
  [ "$fillN" -gt 20 ] && fillN=20
  lablen=${#label}                                 # label spans cols 1..lablen
  local out="" last="" i ch fg bg b sgr
  for ((i=0; i<20; i++)); do
    ch="${bartext:i:1}"
    if [ "$i" -lt "$fillN" ]; then fg="$DARKFG"; bg="$FILLBG"; else fg="$WHITE"; bg="$TRACKBG"; fi
    if [ "$i" -ge 1 ] && [ "$i" -le "$lablen" ]; then b='1;'; else b=''; fi
    sgr="${b}${fg};${bg}"
    [ "$sgr" != "$last" ] && { out="${out}${e}[0m${e}[${sgr}m"; last="$sgr"; }
    out="${out}${ch}"
  done
  printf '%s' "${out}${e}[0m"
}
bar_context=$(usage_bar "$ctx" "Context")
bar_session=$(usage_bar "$five_h" "Session")
bar_week=$(usage_bar "$seven_d" "Week")

# visible width of a string (ANSI stripped; ASCII content -> chars == columns)
vislen() { local s; s=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'); printf '%s' "${#s}"; }

# --- assemble ---
# model line: model(...) on the left, bars right-aligned to the terminal edge
modelbars="$seg_model"
bars=""
for b in "$bar_context" "$bar_session" "$bar_week"; do
  [ -n "$b" ] || continue
  [ -n "$bars" ] && bars="$bars "
  bars="$bars$b"
done
if [ -n "$bars" ]; then
  # drop the trailing styled space on the last bar so it sits flush right
  bars="${bars%" ${e}[0m"}${e}[0m"
  if [ -n "$modelbars" ]; then
    W="${COLUMNS:-$(tput cols 2>/dev/null || echo 0)}"   # Claude Code exports COLUMNS
    case "$W" in ''|*[!0-9]*) W=0;; esac
    mv=$(vislen "$modelbars"); bv=$(vislen "$bars")
    pad=$(( W - RMARGIN - mv - bv ))
    if [ "$W" -gt 0 ] && [ "$pad" -ge 1 ]; then
      modelbars="${modelbars}$(printf '%*s' "$pad" '')${bars}"
    else
      modelbars="${modelbars}  ${bars}"    # doesn't fit -> just space-separate
    fi
  else
    modelbars="$bars"
  fi
fi

# line 1: title  folder
line1=""
for s in "$seg_title" "$seg_folder"; do
  [ -n "$s" ] || continue
  [ -n "$line1" ] && line1="$line1  "
  line1="$line1$s"
done
[ -n "$line1" ] && printf '%s\n' "$line1"
# spacer line before/after model+bars — zero-width space (U+200B). nbsp gets
# trimmed (JS trim() treats it as whitespace); ZWSP is not in the trim set.
NB=$'\342\200\213'
[ -n "$modelbars" ] && printf '%s\n%s\n%s\n' "$NB" "$modelbars" "$NB"
