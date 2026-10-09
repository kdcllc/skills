#!/usr/bin/env node
const assert = require('assert/strict');
const {
  annotateRole,
  buildExtendedRolesPayload,
  loadExtendedRolesPayload,
  loadPermissionIndex,
  matchesAction,
  permissionMatchesRole,
  privilegedPermission,
  rankRoles,
} = require('./lib/rbac');

function assertSortedByHeuristic(matches, contextName) {
  let seenPrivileged = false;
  let previousPrivileged = false;
  let previousTotal = -1;

  for (const role of matches) {
    if (seenPrivileged && !role.privileged) {
      throw new Error(`${contextName}: non-privileged role appeared after privileged role`);
    }

    if (role.privileged) {
      seenPrivileged = true;
    }

    if (role.privileged !== previousPrivileged) {
      previousTotal = -1;
      previousPrivileged = role.privileged;
    }

    if (role.matchingPermissionsTotal === 0) {
      continue;
    }

    if (role.matchingPermissionsTotal < previousTotal) {
      throw new Error(`${contextName}: matchingPermissionsTotal is not monotonic`);
    }

    previousTotal = role.matchingPermissionsTotal;
  }

  let seenZero = false;
  for (const role of matches) {
    if (role.matchingPermissionsTotal === 0) {
      seenZero = true;
      continue;
    }

    if (seenZero) {
      throw new Error(`${contextName}: role with non-zero matchingPermissionsTotal appeared after zero-total role`);
    }
  }
}

async function main() {
  const [extendedPayload, persistedPayload, permissionIndex] = await Promise.all([
    buildExtendedRolesPayload(),
    loadExtendedRolesPayload(),
    loadPermissionIndex(),
  ]);

  assert.ok(extendedPayload.roles.length > 0, 'Expected built-in roles in references/data/roles.json');
  assert.ok(Object.keys(permissionIndex).length > 0, 'Expected provider operations in references/data/permissions.json');
  assert.equal(persistedPayload.roles.length, extendedPayload.roles.length, 'Persisted extended roles should match raw role count');
  assert.ok(!persistedPayload.roles.some((role) => role.roleName === 'TEST TEST TEST #2'), 'Snapshot should not contain synthetic test role names');

  const snapshotDate = new Date(persistedPayload.lastUpdated);
  assert.ok(!Number.isNaN(snapshotDate.valueOf()), 'roles-extended.json lastUpdated should be a valid ISO date');
  const snapshotAgeDays = Math.floor((Date.now() - snapshotDate.valueOf()) / (1000 * 60 * 60 * 24));
  if (snapshotAgeDays > 180) {
    console.warn(`Warning: roles-extended snapshot is ${snapshotAgeDays} days old. Consider running scripts/generate-json.sh`);
  }

  assert.equal(matchesAction('Microsoft.Support/services/read', 'Microsoft.Support/*'), true, 'Wildcard action pattern should match valid action');
  assert.equal(matchesAction('Microsoft.Support/services/read', 'Microsoft.Compute/*'), false, 'Wildcard action pattern should not match unrelated provider');

  const privilegedRoles = persistedPayload.roles.filter((role) => role.privileged);
  assert.ok(privilegedRoles.length > 0, 'Expected at least one privileged role');
  assert.ok(privilegedRoles.every((role) => permissionMatchesRole(privilegedPermission, role, permissionIndex)), 'Privileged role annotations should match runtime evaluation');

  const supportMatches = rankRoles(['Microsoft.Support/services/read'], persistedPayload.roles, permissionIndex);
  assert.ok(supportMatches.length > 0, 'Expected at least one role for Microsoft.Support/services/read');
  assert.ok(supportMatches.some((role) => role.roleName === 'Support Request Contributor'), 'Expected Support Request Contributor to remain in the candidate set');
  assertSortedByHeuristic(supportMatches, 'supportMatches');

  const webMatches = rankRoles(['Microsoft.Web/sites/read', 'Microsoft.Web/sites/write'], persistedPayload.roles, permissionIndex);
  assert.ok(webMatches.length > 0, 'Expected at least one role for Microsoft.Web/sites/read + write');
  assert.ok(webMatches.every((role) => permissionMatchesRole('Microsoft.Web/sites/read', role, permissionIndex) && permissionMatchesRole('Microsoft.Web/sites/write', role, permissionIndex)), 'Web multi-permission ranking should only return full-set matches');
  assertSortedByHeuristic(webMatches, 'webMatches');

  const privilegedMatches = rankRoles([privilegedPermission], persistedPayload.roles, permissionIndex);
  assert.ok(privilegedMatches.length > 0, 'Expected at least one role that can assign role assignments');
  assert.ok(privilegedMatches.every((role) => role.privileged), 'roleAssignments/write matches should all be marked privileged');

  const contributor = persistedPayload.roles.find((role) => role.roleName === 'Contributor');
  assert.ok(contributor, 'Expected Contributor role in snapshot');
  assert.equal(permissionMatchesRole('Microsoft.Authorization/roleAssignments/write', contributor, permissionIndex), false, 'Contributor notActions should block roleAssignments/write');

  const owner = persistedPayload.roles.find((role) => role.roleName === 'Owner');
  assert.ok(owner, 'Expected Owner role in snapshot');
  assert.equal(permissionMatchesRole('Microsoft.Authorization/roleAssignments/write', owner, permissionIndex), true, 'Owner should allow roleAssignments/write');

  const reAnnotatedOwner = annotateRole(owner, permissionIndex);
  assert.equal(reAnnotatedOwner.privileged, true, 'Owner should be annotated as privileged');

  const noMatch = rankRoles(['Microsoft.Example/doesNotExist/read'], persistedPayload.roles, permissionIndex);
  assert.equal(noMatch.length, 0, 'Unknown permissions should not return a built-in role');

  console.log(`Validated ${persistedPayload.roles.length} roles and ${Object.keys(permissionIndex).length} permissions.`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
