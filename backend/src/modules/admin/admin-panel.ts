import { readdir, readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import type { FastifyPluginAsync } from 'fastify';

const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
};

/**
 * Serves the web admin panel (the static files in `dir`) at /admin/, from the
 * same origin as the API so it needs no CORS. Files are read once at start-up;
 * only names in that folder can be served, so no path can escape it.
 */
export function adminPanel(dir: string): FastifyPluginAsync {
  return async (app) => {
    const files = new Map<string, { body: Buffer; type: string }>();
    let names: string[];
    try {
      names = (await readdir(dir, { withFileTypes: true })).filter((e) => e.isFile()).map((e) => e.name);
    } catch {
      app.log.warn({ dir }, 'admin panel folder not found: /admin is off');
      return;
    }
    for (const name of names) {
      const type = TYPES[extname(name).toLowerCase()];
      if (type) files.set(name, { body: await readFile(join(dir, name)), type });
    }

    const send = (name: string) => files.get(name);

    app.get('/admin', (_request, reply) => reply.redirect('/admin/'));
    app.get('/admin/', (_request, reply) => {
      const file = send('index.html');
      if (!file) return reply.callNotFound();
      return reply.header('cache-control', 'no-cache').type(file.type).send(file.body);
    });
    app.get<{ Params: { file: string } }>('/admin/:file', (request, reply) => {
      const file = send(request.params.file);
      if (!file) return reply.callNotFound();
      return reply.header('cache-control', 'no-cache').type(file.type).send(file.body);
    });
  };
}
