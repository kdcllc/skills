#!/usr/bin/env node
const fs = require('fs/promises');
const {
  buildExtendedRolesPayload,
  defaultExtendedRolesPath,
} = require('./lib/rbac');

async function main() {
  const payload = await buildExtendedRolesPayload();
  await fs.writeFile(defaultExtendedRolesPath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  console.log(`Wrote ${payload.roles.length} extended roles to ${defaultExtendedRolesPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
