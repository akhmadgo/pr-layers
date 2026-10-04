#!/bin/sh
# PreToolUse guard for the pr-layers analyst agent. Runs on every tool call
# in the session, so the common case (not the analyst) exits immediately.
input=$(cat)
case "$input" in
  *pr-layers:layer-analyst*) ;;
  *) exit 0 ;;
esac
if ! command -v python3 >/dev/null 2>&1; then
  echo "pr-layers guard: python3 not found, blocking analyst tool call" >&2
  exit 2
fi
printf '%s' "$input" | exec python3 "$(dirname "$0")/guard.py"
