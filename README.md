# pr-layers

A Claude Code skill that splits a pull request into three layers, so a human reviewer knows where to spend attention:

| Layer | What it is | How to review |
|---|---|---|
| **Domain** | The thing you're actually building: business rules, behavior, data-model meaning, API contract | Read closely |
| **Platform** | Code that exists because of your cloud provider or vendors: SDK calls, IAM, Terraform, CI, env vars, Stripe/Twilio/etc. | Check blast radius, security, cost |
| **Language** | Code that exists because of your language/framework: types, imports, error-wrapping, DI wiring, refactors, dependency bumps | Skim |

The test for each hunk: *if we rewrote this system in a different language on a different cloud, would this change still have to exist?*

It also lists **hidden domain decisions**: product choices buried in plumbing, such as an S3 key that encodes data ownership, a retry count that changes user-visible behavior, an IAM policy that is really a permission rule, or a `catch` that swallows an error. For each one it says whether the PR description mentions it.

## Install

In Claude Code:

```
/plugin marketplace add akhmadgo/pr-layers
/plugin install pr-layers@pr-layers
```

Or copy `skills/pr-layers/` into `~/.claude/skills/`.

## Use

```
/pr-layers 123            # GitHub PR number (needs the gh CLI)
/pr-layers my-branch      # branch vs. its base
/pr-layers main..feature  # any range
/pr-layers                # current branch vs. its base, plus uncommitted changes
```

Or ask in plain words: "break down this PR".

## Output

- What the PR changes about the product, in 1–3 sentences
- Approximate lines changed per layer
- Hidden domain decisions
- Domain / Platform / Language sections with `file:line` ranges
- A suggested reading order

To have agents attach this to every PR they open, add to your repo's `CLAUDE.md`:

> After opening a PR, run /pr-layers and add its output to the PR description.

## License

MIT
