// Switches the Prisma datasource provider in prisma/schema.prisma.
//
//   node scripts/prisma-provider.mjs postgresql   # on the production host (Render), before `prisma generate`
//   node scripts/prisma-provider.mjs sqlite       # back to local development
//
// Development and the tests use SQLite; production uses Postgres. The schema avoids
// provider-specific types, so the same models work on both.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const provider = process.argv[2];
if (provider !== 'postgresql' && provider !== 'sqlite') {
  console.error('Usage: node scripts/prisma-provider.mjs postgresql|sqlite');
  process.exit(2);
}
const file = fileURLToPath(new URL('../prisma/schema.prisma', import.meta.url));
const schema = readFileSync(file, 'utf8');
const next = schema.replace(/(datasource db \{\s*provider\s*=\s*)"(sqlite|postgresql)"/, `$1"${provider}"`);
if (next === schema && !schema.includes(`provider = "${provider}"`)) {
  console.error('Could not find the datasource provider in prisma/schema.prisma');
  process.exit(1);
}
writeFileSync(file, next);
console.log(`Prisma provider: ${provider}`);
