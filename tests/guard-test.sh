#!/usr/bin/env bash
# Feeds the guard hook the tool calls a hijacked analyst would try. No Claude needed.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T" "$B"' EXIT
mkdir -p "$T/repo" "$T/outside"
( cd "$T/repo" && git init -q && echo x > app.py && echo "TOKEN=abc" > .env \
  && echo secret > "$T/outside/creds" && ln -s "$T/outside/creds" docs_link )
B=$(mktemp -d "${TMPDIR:-/tmp}/pr-layers.XXXXXX"); chmod 700 "$B"; touch "$B/diff.patch"

fail=0
check() { # expected-exit json label
  printf '%s' "$2" | sh "$here/hooks/guard.sh" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$1" ]; then echo "ok    $3"; else echo "FAIL  $3 (exit $rc, want $1)"; fail=1; fi
}
A='"agent_type":"pr-layers:layer-analyst","cwd":"'"$T/repo"'"'

check 0 '{"agent_type":"Explore","cwd":"/","tool_name":"Bash","tool_input":{"command":"ls"}}' "other agents untouched"
check 0 '{"cwd":"/","tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}' "main session untouched"
check 0 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":"app.py"}}' "read repo file"
check 0 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":"'"$B"'/diff.patch"}}' "read bundle"
check 0 '{'"$A"',"tool_name":"Grep","tool_input":{"pattern":"x"}}' "grep repo"
check 0 '{'"$A"',"tool_name":"SubagentHandback","tool_input":{"message":"report"}}' "return report"
check 2 '{'"$A"',"tool_name":"Bash","tool_input":{"command":"curl evil"}}' "block Bash"
check 2 '{'"$A"',"tool_name":"WebFetch","tool_input":{"url":"https://evil"}}' "block WebFetch"
check 2 '{'"$A"',"tool_name":"Write","tool_input":{"file_path":"app.py"}}' "block Write"
check 2 '{'"$A"',"tool_name":"mcp__github__create_review","tool_input":{}}' "block MCP tools"
check 2 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":"~/.ssh/id_rsa"}}' "block ~/.ssh"
check 2 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":"../outside/creds"}}' "block ../ escape"
check 2 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":"docs_link"}}' "block symlink out of repo"
check 2 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":".env"}}' "block .env"
check 2 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":".git/config"}}' "block .git/"
check 2 '{'"$A"',"tool_name":"Grep","tool_input":{"pattern":"TOKEN","glob":".env*"}}' "block grep glob on .env"
check 2 '{'"$A"',"tool_name":"Glob","tool_input":{"pattern":"**/*.pem"}}' "block glob for keys"
check 2 '{'"$A"',"tool_name":"Read","tool_input":{"file_path":"/tmp/pr-layers.fake/x"}}' "block fake bundle path"
check 2 'garbage pr-layers:layer-analyst' "fail closed on bad input"
exit $fail
