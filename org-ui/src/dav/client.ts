// Minimal WebDAV client: PROPFIND (Depth: 1), GET with ETag, conditional PUT.
// Auth works like organice: Basic credentials sent by the app on every request.

export interface DavAuth {
  url: string; // base URL ending with "/"
  user: string;
  password: string;
}

export interface DavEntry {
  path: string; // relative to the base, e.g. "tasks.org"
  name: string;
  isDirectory: boolean;
}

export interface DavFile {
  text: string;
  etag: string | null;
}

export class DavError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

/** Thrown for network failures (offline, DNS, TLS) as opposed to HTTP errors. */
export class DavNetworkError extends Error {}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function basic(user: string, password: string): string {
  const bytes = new TextEncoder().encode(`${user}:${password}`);
  let bin = '';
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return 'Basic ' + btoa(bin);
}

export function normalizeBase(url: string): string {
  return url.endsWith('/') ? url : url + '/';
}

function encodePath(path: string): string {
  return path.split('/').map(encodeURIComponent).join('/');
}

export function isWeakEtag(etag: string | null): boolean {
  return !!etag && /^W\//i.test(etag);
}

/** Parse a PROPFIND multistatus body into entries directly below BASE_PATH. */
export function parsePropfind(xml: string, basePath: string, parser: DOMParser = new DOMParser()): DavEntry[] {
  const doc = parser.parseFromString(xml, 'application/xml');
  const NS = 'DAV:';
  const out: DavEntry[] = [];
  const base = decodeURIComponent(basePath.endsWith('/') ? basePath : basePath + '/');
  for (const resp of Array.from(doc.getElementsByTagNameNS(NS, 'response'))) {
    const hrefEl = resp.getElementsByTagNameNS(NS, 'href')[0];
    if (!hrefEl?.textContent) continue;
    let href = hrefEl.textContent.trim();
    try {
      href = new URL(href, 'http://x').pathname;
    } catch {
      /* keep as is */
    }
    href = decodeURIComponent(href);
    if (!href.startsWith(base)) continue;
    let rel = href.slice(base.length);
    const isDirectory =
      resp.getElementsByTagNameNS(NS, 'collection').length > 0 || rel.endsWith('/');
    rel = rel.replace(/\/$/, '');
    if (!rel || rel.includes('/')) continue;
    out.push({ path: rel, name: rel, isDirectory });
  }
  return out;
}

export class DavClient {
  readonly base: string;
  private readonly authHeader: string;
  private readonly fetchImpl: typeof fetch;

  constructor(auth: DavAuth, fetchImpl: typeof fetch = (...a) => fetch(...a)) {
    this.base = normalizeBase(auth.url);
    this.authHeader = basic(auth.user, auth.password);
    this.fetchImpl = fetchImpl;
  }

  private async request(method: string, path: string, init: RequestInit = {}): Promise<Response> {
    const headers = new Headers(init.headers);
    headers.set('Authorization', this.authHeader);
    try {
      return await this.fetchImpl(this.base + encodePath(path), {
        ...init,
        method,
        headers,
        credentials: 'omit',
        cache: 'no-store',
      });
    } catch (e) {
      throw new DavNetworkError(e instanceof Error ? e.message : String(e));
    }
  }

  /** List entries of the root collection. */
  async list(): Promise<DavEntry[]> {
    const r = await this.request('PROPFIND', '', {
      headers: { Depth: '1', 'Content-Type': 'application/xml; charset=utf-8' },
      body: '<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>',
    });
    if (r.status !== 207 && !r.ok) throw new DavError(r.status, `PROPFIND: HTTP ${r.status}`);
    return parsePropfind(await r.text(), new URL(this.base, 'http://x').pathname);
  }

  /**
   * GET PATH. Returns null for 404. A weak ETag (file changed less than a
   * second ago) is re-read a few times so that If-Match gets a strong one.
   */
  async get(path: string): Promise<DavFile | null> {
    for (let attempt = 0; ; attempt++) {
      const r = await this.request('GET', path);
      if (r.status === 404) return null;
      if (!r.ok) throw new DavError(r.status, `GET ${path}: HTTP ${r.status}`);
      const etag = r.headers.get('ETag');
      const text = await r.text();
      if (isWeakEtag(etag) && attempt < 3) {
        await sleep(1100);
        continue;
      }
      return { text, etag };
    }
  }

  /** PUT TEXT to PATH; IF_MATCH null means "create only if absent". */
  async put(path: string, text: string, ifMatch: string | null): Promise<void> {
    const headers: Record<string, string> = { 'Content-Type': 'text/plain; charset=utf-8' };
    if (ifMatch) headers['If-Match'] = ifMatch;
    else headers['If-None-Match'] = '*';
    const r = await this.request('PUT', path, { headers, body: text });
    if (!r.ok) throw new DavError(r.status, `PUT ${path}: HTTP ${r.status}`);
  }

  /** True when credentials are accepted (401/403 → false, network errors propagate). */
  async checkAuth(): Promise<boolean> {
    try {
      await this.list();
      return true;
    } catch (e) {
      if (e instanceof DavError && (e.status === 401 || e.status === 403)) return false;
      throw e;
    }
  }
}
