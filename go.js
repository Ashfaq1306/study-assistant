// Finds the Study Assistant server's current address and sends the browser there.
// The server runs on a home computer behind a tunnel whose address changes when it restarts;
// scripts/serve-public.ps1 keeps the latest one in this gist.
const ENDPOINT =
  'https://gist.githubusercontent.com/Ashfaq1306/73f5cd0421af834e9965f8680d2ea2b1/raw/study-assistant-endpoint.json';

export async function serverAddress() {
  // The query string skips stale CDN copies of the file.
  const res = await fetch(`${ENDPOINT}?t=${Date.now()}`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const { apiBaseUrl } = await res.json();
  const url = new URL(apiBaseUrl);
  // Only ever forward to an https address.
  if (url.protocol !== 'https:') throw new Error('not https');
  return url.origin;
}

/** Checks the server answers before sending the browser there. */
export async function reachable(origin) {
  try {
    const res = await fetch(`${origin}/health`, { cache: 'no-store' });
    return res.ok;
  } catch {
    return false;
  }
}
