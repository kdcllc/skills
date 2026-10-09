#!/usr/bin/env node
const {
  defaultExtendedRolesPath,
  loadExtendedRolesPayload,
  loadPermissionIndex,
  rankRoles,
} = require('./lib/rbac');

function usage() {
  console.log('Usage: npm run match -- <permission> [permission...]');
}

async function main() {
  const requestedPermissions = process.argv.slice(2).map((value) => value.trim()).filter(Boolean);

  if (requestedPermissions.length === 0) {
    usage();
    process.exitCode = 1;
    return;
  }

  const [payload, permissionIndex] = await Promise.all([
    loadExtendedRolesPayload(defaultExtendedRolesPath),
    loadPermissionIndex(),
  ]);

  const matches = rankRoles(requestedPermissions, payload.roles, permissionIndex).slice(0, 10).map((role) => ({
    roleName: role.roleName,
    id: role.id,
    matchingPermissionsTotal: role.matchingPermissionsTotal,
    privileged: role.privileged,
  }));

  if (matches.length === 0) {
    console.log(JSON.stringify({
      requestedPermissions,
      lastUpdated: payload.lastUpdated,
      recommendation: 'No built-in role matched every requested permission. Consider a custom role.',
      matches: [],
    }, null, 2));
    return;
  }

  console.log(JSON.stringify({
    requestedPermissions,
    lastUpdated: payload.lastUpdated,
    recommendation: 'Top built-in role candidates sorted by least extra permissions first.',
    matches,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
