#!/usr/bin/env bash
# Claude Code's hooks (settings.json) call this when a session needs me: a
# desktop notification and a sound. The hook's JSON comes on stdin.
#   notify.sh done      Stop: the turn ended
#   notify.sh question  Notification: a permission prompt or a question
#   notify.sh error     StopFailure: an API error ended the turn
input=$(cat)
kind=$1
field() { jq -r "$1 // empty" <<<"$input"; }

# Only the main session notifies, not its subagents.
[ -n "$(field .agent_id)" ] && exit 0

# Stop fires whenever a turn ends, also one that only started background work
# (agents, workflows, shells): that work wakes the session again when it ends.
# Stay quiet until nothing is left running.
if [ "$kind" = "done" ] &&[ "$(jq '.background_tasks // [] | length' <<<"$input")" != 0 ]; then
  exit 0
fi

case $kind in
  done)     urgency=critical body="✅ Task finished — ready for you" ;;
  question) urgency=normal   body="❓ $(field '.message // "Waiting on you"')" ;;
  error)    urgency=critical body="❌ $(field '.error_details // .error // "The turn failed"')" ;;
  *) exit 0 ;;
esac

project=$(basename "$(field .cwd)")
notify-send -a "Claude Code" -u "$urgency" "Claude Code${project:+ · $project}" "$body"
# One sound per kind, beside this script (sources and licenses: sounds/NOTICE).
pw-play --media-role Claude "$HOME/.claude/hooks/sounds/$kind.ogg" >/dev/null 2>&1
exit 0
