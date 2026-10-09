#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

az provider operation list > references/data/permissions.json
az role definition list --query "[?roleType=='BuiltInRole'].{id:name,roleName:roleName,permissions:permissions,type:type}" > references/data/roles.json
npm run extend-data

echo "Updated references/data/permissions.json, references/data/roles.json, and references/data/roles-extended.json"
