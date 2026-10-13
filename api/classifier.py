import anthropic
import json
import os

CATEGORIES = {
    "logic":     {"label": "Core Logic",  "color": "#3B82F6"},
    "syntax":    {"label": "Syntax",      "color": "#6B7280"},
    "aws":       {"label": "AWS",         "color": "#F97316"},
    "terraform": {"label": "Terraform",   "color": "#8B5CF6"},
    "ci":        {"label": "CI/CD",       "color": "#D97706"},
    "tests":     {"label": "Tests",       "color": "#16A34A"},
    "deps":      {"label": "Deps",        "color": "#DB2777"},
    "config":    {"label": "Config",      "color": "#0891B2"},
}

REVIEW_ORDER = ["logic", "aws", "terraform", "ci", "tests", "config", "deps", "syntax"]

SYSTEM = """You are a pull request classifier. Classify each changed file into exactly one category.

Categories:
- logic: Core business logic, domain rules, algorithms, API endpoints, data transformations, auth logic, database queries
- syntax: Language boilerplate — type annotations, import ordering, formatting, variable renames, pure structural refactors with zero behavior change
- aws: AWS-specific — IAM policies, S3, Lambda, EC2, RDS, CloudWatch, SNS, SQS, CDK constructs, boto3/aws-sdk calls
- terraform: Infrastructure as code — Terraform HCL, CloudFormation YAML, Pulumi, Ansible playbooks, Helm charts
- ci: CI/CD — GitHub Actions workflows, Dockerfile, docker-compose, Makefile, deployment scripts, build configs
- tests: Test files — unit tests, integration tests, fixtures, mocks, test utilities, coverage config
- deps: Dependency manifests — package.json, requirements.txt, pyproject.toml, go.mod, Cargo.toml, lock files
- config: App configuration — .env templates, feature flags, settings YAML/JSON/TOML, nginx/logging config

Rules:
- A test file for AWS code is "tests", not "aws"
- Terraform calling AWS is "terraform"
- Does the change affect what the system does? "logic". Does it only affect how it's written? "syntax"
- Return only valid JSON, no prose."""


async def classify_files(files, pr_title=None):
    client = anthropic.AsyncAnthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

    file_list = "\n".join(
        f"{i+1}. {f.path}" + (f"\n   +{f.patch[:300]}" if f.patch else "")
        for i, f in enumerate(files)
    )

    prompt = f"""PR: {pr_title or 'untitled'}

Files:
{file_list}

Return JSON in this exact shape:
{{
  "files": [{{"path": "...", "category": "..."}}],
  "summary": {{"by_category": {{}}, "review_order": []}}
}}"""

    msg = await client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        system=SYSTEM,
        messages=[{"role": "user", "content": prompt}],
    )

    text = msg.content[0].text
    start, end = text.find("{"), text.rfind("}") + 1
    data = json.loads(text[start:end])

    # Enrich with labels and colors
    by_cat = {}
    for f in data["files"]:
        cat = f.get("category", "logic")
        if cat not in CATEGORIES:
            cat = "logic"
        f["category"] = cat
        f["label"] = CATEGORIES[cat]["label"]
        f["color"] = CATEGORIES[cat]["color"]
        by_cat[cat] = by_cat.get(cat, 0) + 1

    data["summary"]["by_category"] = by_cat
    data["summary"]["review_order"] = [c for c in REVIEW_ORDER if c in by_cat]

    return data
