---
name: pr-layers
description: Split a PR or diff into three layers so a human can review it fast — DOMAIN (the thing actually being built), LANGUAGE (code that exists because of the programming language/framework), and PLATFORM (code that exists because of the cloud provider or external services). Use when the user says "/pr-layers", asks to "break down this PR", "what's actually new in this PR", "which parts are AWS/GCP stuff", or wants help reviewing a diff they didn't write.
argument-hint: "[PR number | branch | base..head]  (default: current branch vs its base)"
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git merge-base:*), Bash(git rev-parse:*), Bash(git show:*), Bash(gh pr diff:*), Bash(gh pr view:*), Read, Grep, Glob
---

# PR layers

Goal: a reviewer should be able to read only the DOMAIN section and know what the PR
changes about the product, then decide how much attention the other two layers need.

## 1. Get the diff

- PR number → `gh pr view <n> --json title,body,baseRefName,headRefName` and `gh pr diff <n>`
- branch or range → `git diff <base>...<head>`
- nothing given → `git diff $(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD main)...HEAD`
  plus uncommitted changes (`git diff HEAD`) if any

Read the surrounding code of any hunk you can't classify from the diff alone. Classify from
what the code does, not from the file path.

## 2. Classify every hunk

Ask one question per hunk: **"If we rewrote this system in a different language on a
different cloud, would this change still have to exist?"**

| Layer | Survives a rewrite? | Typical contents |
|---|---|---|
| **DOMAIN** | Yes, in both | Business rules, new behavior, state transitions, validation rules, calculations, data model *meaning* (new field, new status, new relationship), public API contract, permission *rules* (who may do what), user-facing text, feature flags' *conditions* |
| **LANGUAGE** | No — gone if we change language/framework | Types/annotations, imports, error-wrapping idioms, async/await plumbing, null handling, serialization/DTO mapping, framework wiring (DI, decorators, routers, middleware registration), ORM mechanics, refactors/renames, lint/format, dependency bumps, build config, generated code |
| **PLATFORM** | No — gone if we change cloud/vendor | Cloud SDK calls (boto3, google-cloud, azure), IAM/policies, Terraform/CDK/Pulumi, k8s/Helm, Dockerfiles, CI/CD, env vars & secrets wiring, queues/topics/buckets, retries/timeouts tuned to a service, third-party vendor APIs (Stripe, Twilio, OpenAI…), observability (metrics, log shipping, tracing) |

Rules:
- Split at line-range granularity. One function often holds all three layers; report each range separately.
- Tests go to the layer they verify. A test asserting a business rule is DOMAIN even if it's full of mocks.
- Migrations: the schema change's *meaning* is DOMAIN; the migration file mechanics are LANGUAGE.
- When unsure between two layers, pick the one that makes the reviewer look harder (DOMAIN > PLATFORM > LANGUAGE) and mark it `(?)`.

## 3. Hunt for hidden domain decisions

This is the step reviewers miss. Find product decisions buried inside LANGUAGE or PLATFORM
code, for example:
- an S3 key / table name / topic name that encodes how data is partitioned or who owns it
- a retry count, timeout, TTL, or queue visibility window that changes user-visible behavior
- an IAM policy that grants or removes access — this is a permission rule
- a default value, an enum fallback, a `catch` that swallows an error and continues
- a serialization change that alters the API response shape
- an `Optional`/nullable change that means "this field can now be missing"

List every one under **Hidden domain decisions**. Each entry: location, what it decides in
plain product terms, and whether the PR description mentions it.

## 4. Output

Write in plain language; assume the reader knows the product but not this code.

```
## <PR title or range>

**What this PR changes about the product** (1–3 sentences, DOMAIN only. If DOMAIN is empty, say "No product behavior change" and stop the summary there.)

| Layer | Lines changed | Files | Review effort |
|---|---|---|---|
| Domain | +x/−y | n | deep |
| Platform | +x/−y | n | check blast radius, security, cost |
| Language | +x/−y | n | skim |

### Hidden domain decisions
1. `path:line` — <decision in product terms> — mentioned in PR description: yes/no

### Domain — read these
- `path:start-end` — what changes in behavior, and the case most likely to break

### Platform — check these
- `path:start-end` — what resource/permission/service changes; blast radius if wrong

### Language — skim
- grouped by kind (e.g. "type annotations across 6 files", "import reshuffle"), not line by line, unless something is non-idiomatic or risky

### Suggested reading order
1. … (domain files first, then the platform pieces they depend on)
```

Line counts come from the diff (`git diff --numstat` per file, then apportioned by your
hunk classification); say they're approximate when a file was split across layers.
