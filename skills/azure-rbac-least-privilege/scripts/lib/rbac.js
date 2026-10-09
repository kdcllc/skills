const fs = require('fs/promises');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const dataDir = path.join(repoRoot, 'references', 'data');
const defaultPermissionsPath = path.join(dataDir, 'permissions.json');
const defaultRolesPath = path.join(dataDir, 'roles.json');
const defaultExtendedRolesPath = path.join(dataDir, 'roles-extended.json');
const privilegedPermission = 'Microsoft.Authorization/roleAssignments/write';

const normalizeAction = (value) => value.trim().toLowerCase();

const wildcardToRegex = (pattern) => new RegExp(`^${pattern.split('*').join('.*')}$`, 'i');

const matchesAction = (action, pattern) => wildcardToRegex(pattern).test(action.trim());

const matchesAnyPattern = (action, patterns = []) => patterns.some((pattern) => matchesAction(action, pattern));

const createPermissionIndex = (providers) => providers.reduce((index, provider) => {
  for (const operation of provider.operations || []) {
    index[normalizeAction(operation.name)] = operation;
  }

  for (const resourceType of provider.resourceTypes || []) {
    for (const operation of resourceType.operations || []) {
      index[normalizeAction(operation.name)] = operation;
    }
  }

  return index;
}, {});

const permissionMatchesRole = (value, role, permissionIndex) => {
  const action = value.trim();
  const roleDefinition = role.permissions?.[0];
  const permission = permissionIndex[normalizeAction(action)];

  if (!roleDefinition || !permission) {
    return false;
  }

  if (permission.isDataAction) {
    return matchesAnyPattern(action, roleDefinition.dataActions) && !matchesAnyPattern(action, roleDefinition.notDataActions);
  }

  return matchesAnyPattern(action, roleDefinition.actions) && !matchesAnyPattern(action, roleDefinition.notActions);
};

const countMatchingPermissions = (role, permissionIndex) => Object.values(permissionIndex).reduce((total, permission) => {
  return total + (permissionMatchesRole(permission.name, role, permissionIndex) ? 1 : 0);
}, 0);

const annotateRole = (role, permissionIndex) => {
  const matchingPermissionsTotal = countMatchingPermissions(role, permissionIndex);
  const privileged = permissionMatchesRole(privilegedPermission, role, permissionIndex);

  return {
    ...role,
    matchingPermissionsTotal,
    privileged,
  };
};

const rankRoles = (requestedPermissions, roles, permissionIndex) => {
  const requested = requestedPermissions.map((value) => value.trim()).filter(Boolean);
  const candidates = roles
    .map((role) => role.matchingPermissionsTotal === undefined || role.privileged === undefined ? annotateRole(role, permissionIndex) : role)
    .filter((role) => requested.every((permission) => permissionMatchesRole(permission, role, permissionIndex)));

  return candidates.sort((left, right) => {
    if (left.privileged !== right.privileged) {
      return left.privileged ? 1 : -1;
    }

    if (left.matchingPermissionsTotal === 0 && right.matchingPermissionsTotal !== 0) {
      return 1;
    }

    if (right.matchingPermissionsTotal === 0 && left.matchingPermissionsTotal !== 0) {
      return -1;
    }

    return left.matchingPermissionsTotal - right.matchingPermissionsTotal || left.roleName.localeCompare(right.roleName);
  });
};

const readJson = async (filePath) => JSON.parse(await fs.readFile(filePath, 'utf8'));

const loadPermissionIndex = async (filePath = defaultPermissionsPath) => createPermissionIndex(await readJson(filePath));

const loadRoles = async (filePath = defaultRolesPath) => readJson(filePath);

const loadExtendedRolesPayload = async (filePath = defaultExtendedRolesPath) => readJson(filePath);

const buildExtendedRolesPayload = async ({ rolesPath = defaultRolesPath, permissionsPath = defaultPermissionsPath, lastUpdated = new Date().toISOString() } = {}) => {
  const [roles, permissionProviders] = await Promise.all([readJson(rolesPath), readJson(permissionsPath)]);
  const permissionIndex = createPermissionIndex(permissionProviders);

  return {
    lastUpdated,
    roles: roles.map((role) => annotateRole(role, permissionIndex)),
  };
};

module.exports = {
  annotateRole,
  buildExtendedRolesPayload,
  countMatchingPermissions,
  createPermissionIndex,
  dataDir,
  defaultExtendedRolesPath,
  defaultPermissionsPath,
  defaultRolesPath,
  loadExtendedRolesPayload,
  loadPermissionIndex,
  loadRoles,
  matchesAction,
  permissionMatchesRole,
  privilegedPermission,
  rankRoles,
  readJson,
};
