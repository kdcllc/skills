---
name: azure-rbac-least-privilege
description: >-
  Recommends the least-privilege Azure built-in RBAC roles for one or more
  requested operations, using an offline snapshot of role definitions and
  provider operations. Use when asked what role to assign, how to minimize
  Azure permissions, or which built-in role is the smallest safe match for a
  service principal, managed identity, app, or CI/CD job.
license: MIT
metadata:
  version: "1.0.0"
  domain: "authorization"
  confidence: "medium"
  source: "observed"
---

# Azure RBAC least privilege (`azure-rbac-least-privilege`)

## Use When

Use this skill when you need least-privilege **built-in** Azure RBAC role candidates from a set of requested operations and can work from checked-in snapshot data.

- Find the smallest built-in role that covers one or more exact operations.
- Validate or compare least-privilege role recommendations before assignment.
- Recommend role candidates for service principals, managed identities, automation, or CI/CD jobs.
- Explain why a broad role appears and surface smaller non-privileged alternatives first.

## Do Not Use When

- You need custom role JSON generation.
- You need live scope reasoning (resource group vs subscription), PIM, ABAC, or deny assignment analysis.
- You need runtime authorization validation against Azure APIs.

## Inputs

- one or more Azure permission strings, such as `Microsoft.Support/services/read`

## Workflow

1. Load `references/data/roles-extended.json` and `references/data/permissions.json`.
2. Evaluate each requested permission with wildcard allow/deny logic:
   - `actions`
   - `notActions`
   - `dataActions`
   - `notDataActions`
3. Use the permission metadata to keep control-plane and data-plane checks separate.
4. Keep only roles that grant **every** requested permission.
5. Rank matches by `matchingPermissionsTotal` ascending, while treating `0` as an unknown-coverage edge case and pushing those candidates later.
6. Flag roles as privileged when they also grant `Microsoft.Authorization/roleAssignments/write`.

The canonical implementation seam is `scripts/lib/rbac.js`. The sample CLI wrapper is `scripts/match-roles.js`.

## Install and Run

```bash
npx skills add kdcllc/skills --skill azure-rbac-least-privilege
```

Run the matcher from this skill folder. It needs Node.js 18+ and has no dependencies, so there is no `npm install` step:

```bash
node scripts/match-roles.js Microsoft.Support/services/read
node scripts/match-roles.js Microsoft.Web/sites/read Microsoft.Web/sites/write
```

The matcher runs entirely offline against the checked-in snapshot. No Azure API calls are made at install time or at match time.

## Agent Integration

Use the shared matcher directly when integrating this skill into another agent flow. Paths are relative to this skill folder:

```javascript
const {
   loadExtendedRolesPayload,
   loadPermissionIndex,
   rankRoles,
} = require('./scripts/lib/rbac');

const [payload, permissionIndex] = await Promise.all([
   loadExtendedRolesPayload(),
   loadPermissionIndex(),
]);

const matches = rankRoles(
   ['Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'],
   payload.roles,
   permissionIndex
);
```

## Outputs

- ranked built-in role candidates
- `matchingPermissionsTotal` for each candidate
- privileged-role flag
- custom-role guidance when no built-in role covers every requested permission

## Boundaries

- The corpus is snapshot-based, not live. Report the snapshot's `lastUpdated` with every recommendation.
- This skill covers Azure built-in roles only. Custom role JSON generation is out of scope.
- This skill does not validate scope-specific access behavior.
- This skill does not handle deny assignments, PIM, ABAC, or broader governance logic.
- `matchingPermissionsTotal` is a size heuristic, not a security score.
- The result list is recommendation guidance, not an enforcement decision.

## Validation

Run from this skill folder. `validate.js` rebuilds the enriched corpus from the raw snapshot and takes about 40 seconds:

```bash
node scripts/validate.js
node scripts/match-roles.js Microsoft.Support/services/read
```

## References

- [README.md](README.md) — install and example prompts
- [references/ALGORITHM.md](references/ALGORITHM.md) — matcher and ranking details
- [references/DATA-REFRESH.md](references/DATA-REFRESH.md) — snapshot refresh process
- [references/OPERATOR-GUIDE.md](references/OPERATOR-GUIDE.md) — human workflow and interpretation guidance
