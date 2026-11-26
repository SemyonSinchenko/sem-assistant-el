import { describe, expect, it } from 'vitest';
import { JSDOM } from 'jsdom';
import { DavError, DavNetworkError, parsePropfind } from './client';
import { appendToFile, saveHeadline } from './ops';
import { DEFAULT_TODO } from '../org/parse';

/** In-memory WebDAV with mod_dav-like If-Match / If-None-Match semantics. */
class FakeDav {
  files = new Map<string, { text: string; v: number }>();
  /** Hook run between GET and PUT to simulate a concurrent writer. */
  onBeforePut: (() => void) | null = null;
  offline = false;
  async get(path: string) {
    if (this.offline) throw new DavNetworkError('offline');
    const f = this.files.get(path);
    return f ? { text: f.text, etag: `"${f.v}"` } : null;
  }
  async put(path: string, text: string, ifMatch: string | null) {
    if (this.offline) throw new DavNetworkError('offline');
    const hook = this.onBeforePut;
    this.onBeforePut = null;
    hook?.();
    const f = this.files.get(path);
    if (ifMatch === null && f) throw new DavError(412, 'exists');
    if (ifMatch !== null && (!f || `"${f.v}"` !== ifMatch)) throw new DavError(412, 'stale');
    this.files.set(path, { text, v: (f?.v ?? 0) + 1 });
  }
}

const noDelay = async () => {};

describe('appendToFile', () => {
  it('appends and creates a missing inbox', async () => {
    const dav = new FakeDav();
    expect((await appendToFile(dav, 'inbox.org', '* a\n', noDelay)).ok).toBe(true);
    expect((await appendToFile(dav, 'inbox.org', '* b\n', noDelay)).ok).toBe(true);
    expect(dav.files.get('inbox.org')!.text).toBe('* a\n* b\n');
  });

  it('two concurrent appends both survive', async () => {
    const dav = new FakeDav();
    dav.files.set('inbox.org', { text: '* old', v: 1 });
    dav.onBeforePut = () => {
      const f = dav.files.get('inbox.org')!;
      dav.files.set('inbox.org', { text: f.text + '\n* other tab\n', v: f.v + 1 });
    };
    const r = await appendToFile(dav, 'inbox.org', '* mine\n', noDelay);
    expect(r.ok).toBe(true);
    expect(dav.files.get('inbox.org')!.text).toBe('* old\n* other tab\n* mine\n');
  });

  it('reports network errors as retryable', async () => {
    const dav = new FakeDav();
    dav.offline = true;
    expect(await appendToFile(dav, 'inbox.org', '* a\n', noDelay)).toMatchObject({ ok: false, retryable: true });
  });
});

describe('saveHeadline', () => {
  const text = '* TODO A\nbody\n* B\n';
  const target = { path: 't.org', id: null, line: 0, lineText: '* TODO A', sectionLines: ['* TODO A', 'body'] };

  it('saves an edit', async () => {
    const dav = new FakeDav();
    dav.files.set('t.org', { text, v: 1 });
    const r = await saveHeadline(dav, target, { keyword: 'NEXT' }, DEFAULT_TODO);
    expect(r.ok).toBe(true);
    expect(dav.files.get('t.org')!.text).toBe('* NEXT A\nbody\n* B\n');
  });

  it('follows a headline that moved but did not change', async () => {
    const dav = new FakeDav();
    dav.files.set('t.org', { text: '* New\n' + text, v: 1 });
    expect((await saveHeadline(dav, target, { title: 'A2' }, DEFAULT_TODO)).ok).toBe(true);
    expect(dav.files.get('t.org')!.text).toBe('* New\n* TODO A2\nbody\n* B\n');
  });

  it('reports a conflict when the headline changed on the server', async () => {
    const dav = new FakeDav();
    dav.files.set('t.org', { text: '* TODO A\nchanged elsewhere\n* B\n', v: 1 });
    const r = await saveHeadline(dav, target, { title: 'A2' }, DEFAULT_TODO);
    expect(r).toMatchObject({ ok: false, conflict: true });
    expect((await saveHeadline(dav, target, { title: 'A2' }, DEFAULT_TODO, true)).ok).toBe(true);
  });
});

describe('parsePropfind', () => {
  it('returns direct children only', () => {
    const xml = `<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">
      <D:response><D:href>/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
      <D:response><D:href>/tasks.org</D:href><D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat></D:response>
      <D:response><D:href>/inbox%20mobile.org</D:href><D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat></D:response>
      <D:response><D:href>/prompts/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
    </D:multistatus>`;
    const parser = new new JSDOM('').window.DOMParser();
    expect(parsePropfind(xml, '/', parser)).toEqual([
      { path: 'tasks.org', name: 'tasks.org', isDirectory: false },
      { path: 'inbox mobile.org', name: 'inbox mobile.org', isDirectory: false },
      { path: 'prompts', name: 'prompts', isDirectory: true },
    ]);
  });
});
