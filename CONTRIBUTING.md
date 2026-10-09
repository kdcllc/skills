# Contributing

Read [AGENTS.md](AGENTS.md) first. It has the layout and frontmatter rules that the validator enforces.

## Add a new skill

1. Scaffold the folder:

   ```bash
   bash scripts/new-skill.sh my-new-skill
   ```

   This creates `skills/my-new-skill/SKILL.md` from [templates/SKILL.md.tmpl](templates/SKILL.md.tmpl) and prints a README catalog row.

2. Write the `description` (what it does and when to use it, at most 1024 characters) and the instructions. Keep `SKILL.md` under 500 lines; move long material into `references/`, executable helpers into `scripts/`, and templates or static files into `assets/`.
3. Paste the printed row into the Skills table in [README.md](README.md).
4. Optionally add the skill to a domain bundle (see below) and to `skills.sh.json`.
5. Validate:

   ```bash
   bash scripts/validate-skills.sh
   npx skills add . --list
   ```

## Migrate a skill from an existing repo

1. Copy the skill folder from the old repo's `skills/<name>/` into `skills/<name>/` here. Copy only what the skill needs at runtime (`SKILL.md`, `scripts/`, `references/`, `assets/`, `evals/`). Leave behind repo scaffolding such as `.squad/`, `.copilot/skills/`, `CLAUDE.md`, and root `plugin.json` files.
2. Fix the frontmatter so it uses only the six spec fields. For example, move `argument-hint` into `metadata`:

   ```yaml
   metadata:
     argument-hint: "NT reference and target English or Greek word, e.g. Ephesians 2:8 grace"
   ```

   Custom keys like `domain`, `confidence`, and `source` also go under `metadata`.
3. If the skill isn't MIT, set `license` (for example `license: CC-BY-SA-4.0`) and add the full license text as `skills/<name>/LICENSE.txt`.
4. Fix any paths in the instructions or scripts that assumed the old repo layout (for example a repo-root `scripts/` folder).
5. Add a row to the Skills table in [README.md](README.md), and add the skill to a domain bundle if it belongs to one.
6. Run the validator and `npx skills add . --list`.
7. In the old repo, replace the README with a pointer to the new location, for example `npx skills add kdcllc/skills --skill <name>`, then archive the repo on GitHub.

## Domain bundles (Claude Code, Copilot CLI, Codex)

The `kdcllc-skills` plugin in [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json) has no `skills` list, so it loads every folder under `skills/`. To offer smaller bundles, add more entries that list skills explicitly. Paths must start with `./`, and plugin names must not start with `claude-`, `anthropic-`, or `cc-plugin-`.

```json
{
  "name": "kdcllc-azure",
  "description": "Azure RBAC and Terraform skills",
  "source": "./",
  "strict": false,
  "skills": [
    "./skills/azure-rbac-role-matching",
    "./skills/terraform-azure"
  ]
}
```

Users then run `/plugin install kdcllc-azure@kdcllc`. The Cursor marketplace schema doesn't allow a `skills` list on an entry, so Cursor keeps the single `kdcllc-skills` plugin.

## skills.sh groupings

Once the repo has a few skills, add a `skills.sh.json` at the root to group them on the [skills.sh](https://skills.sh/kdcllc/skills) repo page. The schema requires at least one grouping with at least one skill, so don't add the file while `skills/` is empty.

```json
{
  "$schema": "https://skills.sh/schemas/skills.sh.schema.json",
  "notGrouped": "bottom",
  "groupings": [
    {
      "title": "Azure",
      "description": "Least-privilege RBAC and Terraform for Azure.",
      "skills": ["azure-rbac-role-matching", "terraform-azure"]
    }
  ]
}
```

skills.sh picks up changes the next time someone installs from the repo. There is no submission step; the repo appears on the leaderboard once people install from it.

## Releases

- `npx skills`, Claude Code, Copilot CLI, Codex, and Cursor all install from the default branch. Marketplace entries don't set `version`, so Claude Code tracks the latest commit.
- `gh skill install` uses the latest tagged GitHub release and falls back to the default branch only when there are no releases. Tag a release whenever skills change in a way users should pick up.

Release steps:

1. Make sure `master` is green in CI.
2. Check the repo with the GitHub CLI (`gh` 2.90 or newer):

   ```bash
   gh skill publish --dry-run
   ```

3. Publish. `gh skill publish` validates the skills, adds the `agent-skills` topic, and creates the release. Without it, the equivalent is:

   ```bash
   gh repo edit kdcllc/skills --add-topic agent-skills
   gh release create vX.Y.Z --generate-notes
   ```

Use [semantic versioning](https://semver.org): bump the major version when a skill is removed or renamed, the minor version when one is added, and the patch version for fixes.
