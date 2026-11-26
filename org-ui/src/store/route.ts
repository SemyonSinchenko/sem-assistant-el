// Hash routing: #files/<path>, #calendar/<view>/<date>, #new/<template>, #edit/<path>/<line>.

export type CalView = 'timeGridDay' | 'timeGridWeek' | 'dayGridMonth';

export type Route =
  | { view: 'files'; path: string | null }
  | { view: 'calendar'; cal: CalView | null; date: string | null }
  | { view: 'new'; template: string; text: string }
  | { view: 'edit'; path: string; line: number };

const CAL_VIEWS: CalView[] = ['timeGridDay', 'timeGridWeek', 'dayGridMonth'];

export function parseHash(hash: string): Route {
  const h = hash.replace(/^#/, '');
  const [head, ...rest] = h.split('/');
  const dec = (s: string) => {
    try {
      return decodeURIComponent(s);
    } catch {
      return s;
    }
  };
  switch (head) {
    case 'calendar': {
      const cal = CAL_VIEWS.includes(rest[0] as CalView) ? (rest[0] as CalView) : null;
      const date = /^\d{4}-\d{2}-\d{2}$/.test(rest[1] ?? '') ? rest[1] : null;
      return { view: 'calendar', cal, date };
    }
    case 'new': {
      const [tpl, query] = (rest.join('/') || '').split('?');
      const text = new URLSearchParams(query ?? '').get('text') ?? '';
      return { view: 'new', template: dec(tpl), text };
    }
    case 'edit': {
      const line = Number(rest[rest.length - 1]);
      const path = rest.slice(0, -1).map(dec).join('/');
      if (path && Number.isInteger(line)) return { view: 'edit', path, line };
      return { view: 'files', path: null };
    }
    case 'files':
      return { view: 'files', path: rest.length ? rest.map(dec).join('/') || null : null };
    default:
      return { view: 'files', path: null };
  }
}

export function formatHash(r: Route): string {
  const enc = (p: string) => p.split('/').map(encodeURIComponent).join('/');
  switch (r.view) {
    case 'files':
      return '#files' + (r.path ? '/' + enc(r.path) : '');
    case 'calendar':
      return '#calendar' + (r.cal ? '/' + r.cal + (r.date ? '/' + r.date : '') : '');
    case 'new':
      return '#new/' + encodeURIComponent(r.template) + (r.text ? '?text=' + encodeURIComponent(r.text) : '');
    case 'edit':
      return `#edit/${enc(r.path)}/${r.line}`;
  }
}

export function navigate(r: Route, replace = false): void {
  const hash = formatHash(r);
  if (location.hash === hash) return;
  if (replace) history.replaceState(null, '', hash);
  else location.hash = hash;
  if (replace) window.dispatchEvent(new HashChangeEvent('hashchange'));
}
