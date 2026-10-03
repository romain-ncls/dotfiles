#!/bin/bash
# Claude Code statusline
# Shows: current directory | git branch | model | context usage | rate limits
# Context and rate-limit segments render as "NN% <progress bar>".

input=$(cat)

# --- locate jq (PATH may not include /usr/sbin in the statusline exec env) ---
JQ=$(command -v jq || true)
for candidate in /usr/bin/jq /usr/sbin/jq /usr/local/bin/jq; do
  [ -n "$JQ" ] && break
  [ -x "$candidate" ] && JQ="$candidate"
done
[ -z "$JQ" ] && exit 0

# --- colors (dim variants, safe for terminals with dimmed status line rendering) ---
C_RESET=$'\033[0m'
C_DIR=$'\033[2;36m'      # dim cyan
C_GIT=$'\033[2;35m'      # dim magenta
C_MODEL=$'\033[2;34m'    # dim blue
C_LABEL=$'\033[2;37m'    # dim gray  (segment labels + separators)
C_OK=$'\033[2;32m'       # dim green   (< 60% used)
C_WARN=$'\033[2;33m'     # dim yellow  (60-84% used)
C_HIGH=$'\033[2;31m'     # dim red     (>= 85% used)
C_EMPTY=$'\033[2;90m'    # dim gray    (unfilled bar cells)

# Left-aligned block eighths: each cell resolves to 1/8th, so a 10-cell bar has
# 80 steps (1.25% per step). Chosen over braille, whose 8 dots are a 2x4 grid --
# only 2 sub-columns horizontally, i.e. coarser than eighths for a linear bar.
BAR_FILL='█'
BAR_EMPTY='░'
BAR_PARTIAL=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')

# --- one parse pass: cwd, model, ctx%, 5h%, 7d% separated by US (0x1f).
# A non-whitespace delimiter is required: bash `read` collapses runs of
# IFS-whitespace (tabs/spaces), which would shift values into the wrong slots
# whenever a middle field is empty. ---
fields=$("$JQ" -r '
  def n: if . == null then "" else tostring end;
  [ (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (try .context_window.used_percentage catch null | n),
    (try .rate_limits.five_hour.used_percentage catch null | n),
    (try .rate_limits.seven_day.used_percentage catch null | n)
  ] | map(gsub("[\n]"; " ")) | join("")
' <<<"$input" 2>/dev/null)

IFS=$'\x1f' read -r cwd model ctx five week <<<"$fields"

# meter LABEL PERCENT WIDTH -> "LABEL NN% ███▍░░░░", bar colored by threshold.
# Resolution is eighths of a cell: total = round(pct/100 * width * 8), rendered
# as `total/8` full blocks plus one partial block for the remainder. A non-zero
# percentage never renders as an empty bar, and only a true 100% fills the last
# cell -- so 99.9% still reads visibly short of full.
meter() {
  local label=$1 pct=$2 width=$3
  local rounded eighths full part color
  read -r eighths rounded < <(awk -v p="$pct" -v w="$width" 'BEGIN{
    r = int(p + 0.5)
    # never let the label claim 100% while the bar is deliberately short of full
    if (r >= 100 && p < 100) r = 99
    if (r < 0) r = 0
    max = w * 8
    e = int(p * max / 100 + 0.5)
    if (e < 1 && r > 0) e = 1
    if (e >= max && p < 100) e = max - 1
    if (e > max) e = max
    if (e < 0) e = 0
    print e, r
  }')
  full=$((eighths / 8))
  part=$((eighths % 8))
  if   [ "$rounded" -ge 85 ]; then color=$C_HIGH
  elif [ "$rounded" -ge 60 ]; then color=$C_WARN
  else                             color=$C_OK
  fi
  local bar="" rest="" i
  for ((i = 0; i < full; i++)); do bar+="$BAR_FILL"; done
  [ "$part" -gt 0 ] && bar+="${BAR_PARTIAL[$part]}"
  # a partial block occupies a cell, so it consumes one of the empty ones
  local used=$((full + (part > 0 ? 1 : 0)))
  for ((i = used; i < width; i++)); do rest+="$BAR_EMPTY"; done
  printf '%s%s %s%3s%% %s%s%s%s' \
    "$C_LABEL" "$label" "$color" "$rounded" "$bar" "$C_EMPTY" "$rest" "$C_RESET"
}

segments=()

# --- 1. current directory (shortened with ~) ---
if [ -n "$cwd" ]; then
  segments+=("${C_DIR}${cwd/#$HOME/\~}${C_RESET}")
fi

# --- 2. git branch (omitted when not in a repo / detached HEAD) ---
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git --no-optional-locks -C "$cwd" branch --show-current 2>/dev/null)
  [ -n "$branch" ] && segments+=("${C_GIT}${branch}${C_RESET}")
fi

# --- 3. model display name ---
[ -n "$model" ] && segments+=("${C_MODEL}${model}${C_RESET}")

# --- 4. context window usage ---
[ -n "$ctx" ] && segments+=("$(meter ctx "$ctx" 10)")

# --- 5. Claude.ai rate limit usage (5h / 7d), either or both ---
rate=""
[ -n "$five" ] && rate="$(meter 5h "$five" 6)"
if [ -n "$week" ]; then
  [ -n "$rate" ] && rate="$rate  "
  rate="${rate}$(meter 7d "$week" 6)"
fi
[ -n "$rate" ] && segments+=("$rate")

# --- join on one line with a dim separator ---
sep="${C_LABEL} | ${C_RESET}"
out=""
for seg in "${segments[@]}"; do
  if [ -z "$out" ]; then out="$seg"; else out="${out}${sep}${seg}"; fi
done

printf '%s' "$out"
