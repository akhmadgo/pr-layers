"""Enforce the pr-layers analyst sandbox.

The analyst reads attacker-controlled diffs, so it is treated as compromised:
it may only use Read, Grep and Glob, only inside the repository and its own
temp bundle, never on secret-looking files, and never through symlinks that
point elsewhere. Anything else is blocked (exit 2). Any error fails closed.
"""
import fnmatch
import json
import os
import subprocess
import sys

AGENT = "pr-layers:layer-analyst"
TOOLS = {"Read", "Grep", "Glob"}
# How a subagent returns its report to the parent; carries no side effects.
HANDBACK = {"SubagentHandback"}
SECRET_NAMES = [
    ".env", ".env.*", "*.env", ".envrc", "*.pem", "*.key", "*.p12", "*.pfx",
    "id_rsa*", "id_dsa*", "id_ecdsa*", "id_ed25519*", ".netrc", ".npmrc",
    ".pypirc", ".git-credentials", "credentials", "credentials.*",
    "*.tfstate", "*.tfstate.*", "*.tfvars", "secrets.*", "*.kubeconfig",
]


def log(line):
    dest = os.environ.get("PR_LAYERS_GUARD_LOG")
    if dest:
        with open(dest, "a") as f:
            f.write(line + "\n")


def block(reason):
    log(f"BLOCK {reason}")
    print(f"pr-layers guard: {reason}", file=sys.stderr)
    sys.exit(2)


def repo_root(cwd):
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0 and out.stdout.strip():
            return os.path.realpath(out.stdout.strip())
    except Exception:
        pass
    return os.path.realpath(cwd)


def inside(path, root):
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def in_bundle(path):
    """True inside a private pr-layers.XXXXXX dir made by fetch-diff.sh.

    Matched by name and ownership rather than $TMPDIR, because the Bash tool
    and hooks may see different temp dirs.
    """
    d = path
    while d != os.path.dirname(d):
        if os.path.basename(d).startswith("pr-layers."):
            try:
                st = os.stat(d)
            except OSError:
                return False
            return st.st_uid == os.getuid() and (st.st_mode & 0o077) == 0
        d = os.path.dirname(d)
    return False


def secret(path):
    parts = path.split(os.sep)
    if ".git" in parts or ".ssh" in parts or ".aws" in parts or ".gnupg" in parts:
        return True
    name = parts[-1]
    return any(fnmatch.fnmatch(name, pat) for pat in SECRET_NAMES)


def main():
    data = json.load(sys.stdin)
    if data.get("agent_type") != AGENT:
        sys.exit(0)

    tool = data.get("tool_name", "")
    if tool in HANDBACK:
        log(f"ALLOW {tool}")
        sys.exit(0)
    if tool not in TOOLS:
        block(f"{tool} is not allowed for the analyst (Read/Grep/Glob only)")

    cwd = data.get("cwd") or os.getcwd()
    ti = data.get("tool_input") or {}
    raw = ti.get("file_path") if tool == "Read" else ti.get("path")
    raw = raw or cwd
    path = os.path.realpath(os.path.join(cwd, os.path.expanduser(raw)))

    if not (inside(path, repo_root(cwd)) or in_bundle(path)):
        block(f"{raw} is outside the repository")
    if secret(path):
        block(f"{raw} looks like a secret or git internals")
    # Glob's pattern and Grep's glob filter can name files directly.
    keys = {"Glob": ("pattern",), "Grep": ("glob",)}.get(tool, ())
    for key in keys:
        val = ti.get(key)
        if isinstance(val, str) and (
            secret(val.replace("/", os.sep))
            or any(s in val for s in (".env", ".ssh", ".aws", ".git/", "id_rsa", ".pem", ".key"))
        ):
            block(f"{key} {val!r} targets secret-looking files")
    log(f"ALLOW {tool} {raw}")
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except Exception as e:
    block(f"guard error, failing closed: {e}")
