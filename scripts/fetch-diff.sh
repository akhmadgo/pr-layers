#!/usr/bin/env bash
# Collects everything pr-layers needs into a private temp directory.
#
# Everything this script fetches (diff, PR title/body, commit messages, file
# names) is attacker-controlled. It is written to files only. Stdout carries
# the bundle path and numbers, never fetched text, so the calling session
# never reads untrusted content.
set -euo pipefail

die() { echo "pr-layers: $*" >&2; exit 1; }

target="${1:-}"
[ $# -le 1 ] || die "expected at most one argument"

# Strict allowlist on the argument: a PR number, a ref, or a ref range.
# Rejects leading '-' so nothing can be smuggled in as a git/gh option.
ref_re='^[A-Za-z0-9_][A-Za-z0-9._/-]*$'
if [ -n "$target" ] && ! [[ "$target" =~ ^[0-9]+$ ]]; then
  base="${target%%..*}"
  head="${target##*..}"; head="${head#.}"
  [[ "$base" =~ $ref_re ]] || die "invalid ref: use a PR number, a branch, or base..head"
  if [ "$base" != "$target" ]; then
    [[ "$head" =~ $ref_re ]] || die "invalid ref: use a PR number, a branch, or base..head"
  fi
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
repo_root="$(git rev-parse --show-toplevel)"

out="$(mktemp -d "${TMPDIR:-/tmp}/pr-layers.XXXXXX")"
chmod 700 "$out"

default_base() {
  local b
  for b in origin/HEAD origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$b^{commit}" >/dev/null; then
      git merge-base "$b" "${1:-HEAD}"
      return
    fi
  done
  die "could not find a base branch (tried origin/HEAD, origin/main, main, master)"
}

if [[ "$target" =~ ^[0-9]+$ ]]; then
  command -v gh >/dev/null || die "gh CLI is required for PR numbers"
  gh pr view "$target" --json number,title,body,author,baseRefName,headRefName,url > "$out/pr.json"
  gh pr view "$target" --json commits --jq '.commits[] | "commit " + .oid + "\n" + .messageHeadline + "\n" + .messageBody + "\n"' > "$out/commits.txt"
  gh pr diff "$target" > "$out/diff.patch"
  mode="pr"
elif [[ "$target" == *..* ]]; then
  git diff --no-color --no-ext-diff "$target" -- > "$out/diff.patch"
  git log --no-color --format='commit %H%n%B' "$target" -- > "$out/commits.txt"
  mode="range"
elif [ -n "$target" ]; then
  git rev-parse --verify --quiet "$target^{commit}" >/dev/null || die "unknown ref"
  b="$(default_base "$target")"
  git diff --no-color --no-ext-diff "$b...$target" -- > "$out/diff.patch"
  git log --no-color --format='commit %H%n%B' "$b..$target" -- > "$out/commits.txt"
  mode="branch"
else
  b="$(default_base HEAD)"
  # Committed work on this branch plus anything uncommitted.
  git diff --no-color --no-ext-diff "$b" -- > "$out/diff.patch"
  git log --no-color --format='commit %H%n%B' "$b..HEAD" -- > "$out/commits.txt"
  mode="working-tree"
fi

git apply --numstat "$out/diff.patch" > "$out/numstat.txt" 2>/dev/null || : > "$out/numstat.txt"

# Invisible / direction-changing characters are a common way to hide
# instructions from human reviewers while the model still reads them.
# Bidi controls, zero-width chars, BOM, and Unicode tag characters.
perl -CSD -ne '
  if (/^\+\+\+ b\/(.*)$/) { $f = $1 }
  if (/[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}-\x{200F}\x{FEFF}\x{E0000}-\x{E007F}]/) {
    ($n = $ARGV) =~ s{.*/}{};
    print "$n line $.", ($n eq "diff.patch" && $f ne "" ? " (in $f)" : ""), "\n";
  }
  close ARGV if eof;
' "$out/diff.patch" "$out/commits.txt" "$out/pr.json" 2>/dev/null > "$out/hidden-unicode.txt" || true

files=$(wc -l < "$out/numstat.txt" | tr -d ' ')
added=$(awk '$1 ~ /^[0-9]+$/ {s+=$1} END {print s+0}' "$out/numstat.txt")
removed=$(awk '$2 ~ /^[0-9]+$/ {s+=$2} END {print s+0}' "$out/numstat.txt")
hidden=$(wc -l < "$out/hidden-unicode.txt" | tr -d ' ')

echo "BUNDLE=$out"
echo "REPO_ROOT=$repo_root"
echo "MODE=$mode FILES=$files ADDED=$added REMOVED=$removed HIDDEN_UNICODE_LINES=$hidden"
