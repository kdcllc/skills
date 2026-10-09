# Data Refresh Guide

Refresh the offline corpus only when you want newer Azure built-in role or provider-operation data checked into the skill.

## Output files

The refresh pipeline maintains:

- `references/data/permissions.json`
- `references/data/roles.json`
- `references/data/roles-extended.json`

`roles-extended.json` is the file consumed by the matcher for ranking. `roles.json` remains as the raw input used to rebuild the enriched payload.

## Prerequisites

1. Azure CLI installed
2. Azure CLI authenticated
3. Permission to list provider operations and built-in role definitions
4. Node.js 18+

## Refresh command

Run from the skill folder (`skills/azure-rbac-least-privilege/` in this repo):

```bash
scripts/generate-json.sh
```

That script:

1. writes provider operations to `references/data/permissions.json`
2. writes built-in role definitions to `references/data/roles.json`
3. runs `npm run extend-data`

`npm run extend-data` uses `scripts/extend-roles-data.js`, which rebuilds `references/data/roles-extended.json` through the shared logic in `scripts/lib/rbac.js`.

## Post-refresh validation

Always run:

```bash
npm run validate
```

Optional spot check:

```bash
npm run match -- Microsoft.Support/services/read
```

## Troubleshooting

### `scripts/generate-json.sh` fails

- confirm `az --version`
- confirm `az account show`
- confirm your identity can list built-in roles and provider operations

### `npm run extend-data` fails

- confirm `references/data/roles.json` exists
- confirm `references/data/permissions.json` exists
- rerun the refresh script so the raw inputs are regenerated together

### `npm run validate` fails after refresh

- the enriched payload may be out of sync with the raw corpus
- rerun `npm run extend-data`
- if failure persists, inspect `scripts/lib/rbac.js` assumptions against the latest Azure payload shape

## Data caveats

- The repo is snapshot-based, not live.
- Azure can add or change built-in roles between refreshes.
- Consumers should verify final role assignments in Azure before production use.
