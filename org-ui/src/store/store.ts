// Application state: auth, file cache, outbox, UI flags.

import { create } from 'zustand';
import { DEFAULT_CONFIG, type Config } from '../config';
import { DavClient, DavError, DavNetworkError, normalizeBase, type DavAuth } from '../dav/client';
import { appendToFile } from '../dav/ops';
import { parseOrg, type OrgFile } from '../org/parse';
import { load, removeAll, save } from './persist';
import { parseHash, type Route } from './route';

export interface Cached {
  text: string;
  etag: string | null;
  org: OrgFile;
  fetchedAt: number;
}

export interface OutboxItem {
  id: string;
  path: string;
  entry: string;
  createdAt: number;
  error: string | null;
}

export interface Toast {
  id: number;
  text: string;
  detail?: string;
  action?: { label: string; run: () => void };
  ttl: number;
}

interface State {
  config: Config;
  auth: DavAuth | null;
  client: DavClient | null;
  authState: 'unknown' | 'in' | 'out';
  online: boolean;
  files: string[];
  filesError: string | null;
  cache: Record<string, Cached>;
  loading: Record<string, boolean>;
  errors: Record<string, string>;
  outbox: OutboxItem[];
  flushing: boolean;
  route: Route;
  lastRoute: Route | null;
  drawer: boolean;
  highlight: { path: string; line: number } | null;
  toasts: Toast[];
}

interface Actions {
  setConfig(c: Config): void;
  login(auth: DavAuth): Promise<boolean>;
  logout(): void;
  checkAuth(): Promise<void>;
  refreshList(): Promise<void>;
  loadFile(path: string, force?: boolean): Promise<Cached | null>;
  loadAll(force?: boolean): Promise<void>;
  setFile(path: string, text: string, etag: string | null): void;
  capture(entry: string): Promise<'sent' | 'queued' | 'error'>;
  flushOutbox(): Promise<void>;
  setRoute(r: Route): void;
  lastFile(): string;
  setDrawer(open: boolean): void;
  toast(t: Omit<Toast, 'id' | 'ttl'> & { ttl?: number }): void;
  dismissToast(id: number): void;
}

const AUTH_KEYS = { url: 'webdavEndpoint', user: 'webdavUsername', password: 'webdavPassword' };

function loadAuth(): DavAuth | null {
  const url = load<string | null>(AUTH_KEYS.url, null);
  const user = load<string | null>(AUTH_KEYS.user, null);
  const password = load<string | null>(AUTH_KEYS.password, null);
  return url && user !== null && password !== null ? { url, user, password } : null;
}

let toastSeq = 0;
const initialAuth = loadAuth();

export const useStore = create<State & Actions>()((set, get) => ({
  config: DEFAULT_CONFIG,
  auth: initialAuth,
  client: initialAuth ? new DavClient(initialAuth) : null,
  authState: initialAuth ? 'unknown' : 'out',
  online: typeof navigator === 'undefined' ? true : navigator.onLine,
  files: load<string[]>('files', []),
  filesError: null,
  cache: {},
  loading: {},
  errors: {},
  outbox: load<OutboxItem[]>('outbox', []),
  flushing: false,
  route: parseHash(typeof location === 'undefined' ? '' : location.hash),
  lastRoute: null,
  drawer: load<boolean>('drawer', typeof innerWidth === 'undefined' ? true : innerWidth > 760),
  highlight: null,
  toasts: [],

  setConfig: (config) => set({ config }),

  async login(auth) {
    const a = { ...auth, url: normalizeBase(auth.url) };
    const client = new DavClient(a);
    try {
      if (!(await client.checkAuth())) return false;
    } catch {
      // unreachable server: keep credentials like organice does, work offline
    }
    save(AUTH_KEYS.url, a.url);
    save(AUTH_KEYS.user, a.user);
    save(AUTH_KEYS.password, a.password);
    set({ auth: a, client, authState: 'in' });
    void get().refreshList();
    void get().flushOutbox();
    return true;
  },

  logout() {
    const outbox = get().outbox;
    removeAll();
    // never lose captured-but-unsent entries
    if (outbox.length) save('outbox', outbox);
    set({ auth: null, client: null, authState: 'out', cache: {}, files: [] });
  },

  async checkAuth() {
    const c = get().client;
    if (!c) return set({ authState: 'out' });
    try {
      const ok = await c.checkAuth();
      set({ authState: ok ? 'in' : 'out' });
      if (ok) void get().refreshList();
    } catch {
      set({ authState: 'in', online: false });
    }
  },

  async refreshList() {
    const c = get().client;
    if (!c) return;
    try {
      const entries = await c.list();
      const files = entries
        .filter((e) => !e.isDirectory && /\.org$/i.test(e.name))
        .map((e) => e.path)
        .sort((a, b) => a.localeCompare(b, 'en'));
      save('files', files);
      set({ files, filesError: null, online: true });
    } catch (e) {
      if (e instanceof DavError && (e.status === 401 || e.status === 403)) set({ authState: 'out' });
      set({ filesError: (e as Error).message, online: !(e instanceof DavNetworkError) });
    }
  },

  async loadFile(path, force = false) {
    const st = get();
    const cached = st.cache[path];
    if (cached && !force) return cached;
    if (!st.client) return null;
    set((s) => ({ loading: { ...s.loading, [path]: true } }));
    try {
      const r = await st.client.get(path);
      const text = r?.text ?? '';
      const entry: Cached = { text, etag: r?.etag ?? null, org: parseOrg(text, get().config.todoKeywords), fetchedAt: Date.now() };
      set((s) => {
        const errors = { ...s.errors };
        delete errors[path];
        return { cache: { ...s.cache, [path]: entry }, errors, online: true };
      });
      return entry;
    } catch (e) {
      set((s) => ({ errors: { ...s.errors, [path]: (e as Error).message }, online: !(e instanceof DavNetworkError) }));
      return cached ?? null;
    } finally {
      set((s) => ({ loading: { ...s.loading, [path]: false } }));
    }
  },

  async loadAll(force = false) {
    await Promise.all(get().files.map((f) => get().loadFile(f, force)));
  },

  setFile(path, text, etag) {
    const entry: Cached = { text, etag, org: parseOrg(text, get().config.todoKeywords), fetchedAt: Date.now() };
    set((s) => ({ cache: { ...s.cache, [path]: entry } }));
  },

  async capture(entry) {
    const st = get();
    const path = st.config.inbox.path;
    const item: OutboxItem = { id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, path, entry, createdAt: Date.now(), error: null };
    if (!st.client) {
      queue(item, 'нет авторизации');
      return 'queued';
    }
    const r = await appendToFile(st.client, path, entry);
    if (r.ok) {
      get().setFile(path, r.text, null);
      const org = get().cache[path].org;
      const last = org.headlines[org.headlines.length - 1];
      set({ highlight: last ? { path, line: last.line } : null, online: true });
      return 'sent';
    }
    if (r.retryable) {
      queue(item, r.error);
      return 'queued';
    }
    queue(item, r.error);
    return 'error';
  },

  async flushOutbox() {
    const st = get();
    if (st.flushing || !st.outbox.length || !st.client) return;
    set({ flushing: true });
    try {
      for (const item of [...get().outbox]) {
        const r = await appendToFile(get().client!, item.path, item.entry);
        if (r.ok) {
          get().setFile(item.path, r.text, null);
          setOutbox(get().outbox.filter((o) => o.id !== item.id));
        } else {
          setOutbox(get().outbox.map((o) => (o.id === item.id ? { ...o, error: r.error } : o)));
          if (r.retryable) break;
        }
      }
    } finally {
      set({ flushing: false });
    }
  },

  lastFile() {
    return load<string | null>('lastFile', null) ?? get().config.inbox.path;
  },

  setRoute(route) {
    if (route.view === 'files' && route.path) save('lastFile', route.path);
    set((s) => ({ route, lastRoute: s.route }));
  },

  setDrawer(open) {
    if (innerWidth > 760) save('drawer', open);
    set({ drawer: open });
  },

  toast(t) {
    const id = ++toastSeq;
    const toast: Toast = { ttl: 3600, ...t, id };
    set((s) => ({ toasts: [...s.toasts.slice(-2), toast] }));
    setTimeout(() => get().dismissToast(id), toast.ttl);
  },

  dismissToast(id) {
    set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }));
  },
}));

function setOutbox(outbox: OutboxItem[]) {
  save('outbox', outbox.length ? outbox : null);
  useStore.setState({ outbox });
}

function queue(item: OutboxItem, error: string) {
  setOutbox([...useStore.getState().outbox, { ...item, error }]);
}
