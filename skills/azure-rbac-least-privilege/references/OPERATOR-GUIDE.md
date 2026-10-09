# Operator Guide

This guide is for humans using the skill to sanity-check least-privilege built-in Azure RBAC role choices.

## Basic workflow

1. Install the skill:

   ```bash
   npx skills add kdcllc/skills --skill azure-rbac-least-privilege
   ```

2. Identify the exact Azure operations you need.
3. Run the matcher from the installed skill folder (Node.js 18+, no dependencies):

   ```bash
   node scripts/match-roles.js Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read
   ```

4. Review the ranked candidates:
   - smaller `matchingPermissionsTotal` means fewer extra permissions
   - `privileged: true` means the role can assign other roles
5. Verify the recommendation in Azure before assigning it.

## Example scenarios

### Read-only blob access

```bash
node scripts/match-roles.js Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read
```

Expect storage data reader roles near the top. Reject broader candidates when a smaller non-privileged role exists.

### Support ticket access

```bash
node scripts/match-roles.js Microsoft.Support/services/read
```

Use the ranked output to confirm that `Support Request Contributor` remains in the candidate set before assigning anything broader.

### Multi-permission scenario

```bash
node scripts/match-roles.js \
  Microsoft.Web/sites/read \
  Microsoft.Web/sites/write
```

If no built-in role covers the full set, the correct outcome is to consider a custom role rather than stretching to an oversized built-in role by hand.

## How to read the output

The CLI returns JSON with:

- `requestedPermissions`
- `lastUpdated`
- `recommendation`
- `matches`

Each match includes:

- `roleName`
- `id`
- `matchingPermissionsTotal`
- `privileged`

## Data freshness

The matcher uses checked-in snapshots. Inspect `lastUpdated` from:

- `references/data/roles-extended.json`, or
- the CLI output from `node scripts/match-roles.js`

If the snapshot is stale for your scenario, ask a maintainer to run `scripts/generate-json.sh` and then `node scripts/validate.js`.

## Troubleshooting

### No matches returned

Possible causes:

- the requested permission string is wrong
- the permission is newer than the checked-in snapshot
- no built-in role covers the full set

In the last case, a custom role is the honest next step.

### Top result still feels too broad

This repo ranks by least extra permissions in the built-in corpus. It does not guarantee that the smallest built-in role is acceptably narrow for every production scenario. Use Azure-side review before assignment.

### Privileged roles appear

Roles marked `privileged: true` grant `Microsoft.Authorization/roleAssignments/write`. Treat them as higher-risk and prefer non-privileged matches when possible.
