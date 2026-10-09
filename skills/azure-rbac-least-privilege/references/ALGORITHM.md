# Azure RBAC Matching Algorithm

This repo matches requested Azure operations to the smallest built-in RBAC roles in the checked-in offline corpus.

## Corpus

### Enriched roles

`references/data/roles-extended.json` contains:

- built-in role definitions
- `matchingPermissionsTotal`
- `privileged`
- `lastUpdated` at the payload level

### Raw roles

`references/data/roles.json` is the raw built-in role snapshot used to regenerate the enriched payload.

### Permission metadata

`references/data/permissions.json` contains Azure provider operations and the `isDataAction` signal used to dispatch permissions into the correct role arrays.

## Canonical implementation

The shared matcher lives in `scripts/lib/rbac.js`.

Key exported functions:

- `createPermissionIndex()`
- `permissionMatchesRole()`
- `annotateRole()`
- `rankRoles()`
- `buildExtendedRolesPayload()`

The repo intentionally has one matcher seam. `scripts/match-roles.js`, `scripts/validate.js`, and `scripts/extend-roles-data.js` all reuse that module.

## Core logic

### 1. Normalize permissions

Requested operations are trimmed and lower-cased for lookup in the permission index.

### 2. Decide permission type

For each requested operation, the permission metadata decides whether the role should be checked against:

- `actions` / `notActions`
- `dataActions` / `notDataActions`

### 3. Evaluate wildcard allow/deny

Role patterns use `*`. The matcher converts them to case-insensitive regular expressions and applies:

```js
allow && !deny
```

Deny always wins.

### 4. Filter

Only roles that satisfy **every** requested permission survive.

### 5. Annotate and rank

Each surviving role is ranked by:

1. non-privileged before privileged
2. lower `matchingPermissionsTotal` before higher
3. zero `matchingPermissionsTotal` candidates are pushed later as unknown-coverage edge cases
4. role name as a final tiebreaker

Privilege is currently defined as granting `Microsoft.Authorization/roleAssignments/write`.

## Practical implication

The output is a least-extra-permissions heuristic over the built-in corpus. If no role matches, the honest answer is that a custom role is needed.

## Validation hooks

- `npm run validate` confirms the persisted enriched corpus still matches fresh recomputation.
- `npm run match -- <permission>` shows the runtime ranking behavior for concrete inputs.
