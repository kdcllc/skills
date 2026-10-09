# azure-rbac-least-privilege

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/azure-rbac-least-privilege)

Offline Azure built-in RBAC role matching for least-privilege recommendations. Give it one or more Azure operations and it ranks the smallest built-in roles that grant all of them, from a checked-in snapshot of role definitions and provider operations.

## Install

```bash
npx skills add kdcllc/skills --skill azure-rbac-least-privilege
```

Pin to a release:

```bash
npx skills add kdcllc/skills#azure-rbac-least-privilege/v1.0.0 --skill azure-rbac-least-privilege
```

In Claude Code or Copilot CLI, the Azure bundle includes this skill:

```text
/plugin marketplace add kdcllc/skills
/plugin install kdcllc-azure@kdcllc
```

## Example Prompts

- "Use skill azure-rbac-least-privilege. What should you suggest for Key Vault RBAC using least privilege if I only need secrets read?"
- "Use skill azure-rbac-least-privilege and recommend the smallest built-in role for Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read."
- "Use skill azure-rbac-least-privilege for an AI user that only needs OpenAI chat completions and deployment read."

## Commands

Run from this folder with Node.js 18+. There are no dependencies to install.

Run a match:

```bash
node scripts/match-roles.js Microsoft.Support/services/read
```

Validate the offline corpus and matcher (about 40 seconds):

```bash
node scripts/validate.js
```

Refresh the snapshot from Azure (needs `az login`); see [references/DATA-REFRESH.md](references/DATA-REFRESH.md):

```bash
scripts/generate-json.sh
```

## Boundaries

This skill:
- ✅ Matches offline built-in roles from checked-in snapshots
- ✅ Ranks by least-privilege (smallest matching permissions total first)
- ✅ Flags roles that grant `Microsoft.Authorization/roleAssignments/write`
- ❌ Does **not** call Azure APIs at runtime
- ❌ Does **not** generate custom role JSON
- ❌ Does **not** reason about scope, PIM, ABAC, deny assignments, or governance

For full details, see [SKILL.md](SKILL.md). Release history is in [CHANGELOG.md](CHANGELOG.md).
