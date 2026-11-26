// Org timestamps: parsing, formatting with the original style preserved.

export type RepeatUnit = 'h' | 'd' | 'w' | 'm' | 'y';

export interface Repeater {
  kind: '+' | '++' | '.+';
  n: number;
  unit: RepeatUnit;
}

export interface Timestamp {
  active: boolean;
  date: string; // YYYY-MM-DD
  weekday: string | null; // as written in the source, null if absent
  start: string | null; // HH:MM
  end: string | null; // HH:MM
  repeater: Repeater | null;
  /** Raw repeater/warning cookies in source order, e.g. ["+1w", "-2d"]. */
  cookies: string[];
  /** End of a `<a>--<b>` date range. */
  rangeEnd: Timestamp | null;
}

const EN_DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const RU_DOW = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
const DE_DOW = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
const DOW_SETS = [EN_DOW, RU_DOW, DE_DOW];

const SINGLE =
  '([<\\[])(\\d{4}-\\d{2}-\\d{2})' + // open, date
  '(?:[ \\t]+([^\\s\\d<>\\[\\]+.-][^\\s<>\\[\\]]*?))?' + // weekday
  '(?:[ \\t]+(\\d{1,2}:\\d{2})(?:-(\\d{1,2}:\\d{2}))?)?' + // time
  '((?:[ \\t]+(?:\\.\\+|\\+\\+|\\+|--?)\\d+[hdwmy])*)' + // cookies
  '[ \\t]*([>\\]])';

/** Matches one timestamp, optionally followed by `--<range end>`. */
export const TIMESTAMP_RE = new RegExp(`${SINGLE}(?:--${SINGLE})?`, 'g');

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

function normTime(t: string | undefined): string | null {
  if (!t) return null;
  const [h, m] = t.split(':');
  return `${pad2(Number(h))}:${m}`;
}

function parseCookies(raw: string): { cookies: string[]; repeater: Repeater | null } {
  const cookies = raw.trim() ? raw.trim().split(/[ \t]+/) : [];
  let repeater: Repeater | null = null;
  for (const c of cookies) {
    const m = c.match(/^(\.\+|\+\+|\+)(\d+)([hdwmy])$/);
    if (m && !repeater) repeater = { kind: m[1] as Repeater['kind'], n: Number(m[2]), unit: m[3] as RepeatUnit };
  }
  return { cookies, repeater };
}

function fromGroups(g: (string | undefined)[], offset: number): Timestamp {
  const open = g[offset]!;
  const close = g[offset + 6]!;
  const { cookies, repeater } = parseCookies(g[offset + 5] ?? '');
  return {
    active: open === '<' && close === '>',
    date: g[offset + 1]!,
    weekday: g[offset + 2] ?? null,
    start: normTime(g[offset + 3]),
    end: normTime(g[offset + 4]),
    repeater,
    cookies,
    rangeEnd: null,
  };
}

export interface FoundTimestamp {
  ts: Timestamp;
  index: number;
  length: number;
  raw: string;
}

/** Return all well-formed timestamps in TEXT with positions. */
export function findTimestamps(text: string): FoundTimestamp[] {
  const out: FoundTimestamp[] = [];
  TIMESTAMP_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = TIMESTAMP_RE.exec(text))) {
    const g = Array.from(m);
    // brackets must match (<…> or […])
    if ((g[1] === '<') !== (g[7] === '>')) continue;
    const ts = fromGroups(g, 1);
    if (g[8]) ts.rangeEnd = fromGroups(g, 8);
    out.push({ ts, index: m.index, length: m[0].length, raw: m[0] });
  }
  return out;
}

/** Parse a string that consists of exactly one timestamp (or range). */
export function parseTimestamp(s: string): Timestamp | null {
  const found = findTimestamps(s.trim());
  if (found.length !== 1 || found[0].length !== s.trim().length) return null;
  return found[0].ts;
}

/** Weekday name for DATE in the same language and case as SAMPLE. */
export function weekdayFor(date: string, sample: string | null): string {
  const d = dateFromYmd(date);
  const i = d.getDay();
  if (sample) {
    for (const set of DOW_SETS) {
      if (set.some((w) => w.toLowerCase() === sample.toLowerCase())) {
        const w = set[i];
        if (sample === sample.toLowerCase()) return w.toLowerCase();
        if (sample === sample.toUpperCase() && sample.length > 1 && sample !== sample.toLowerCase())
          return w.toUpperCase();
        return w;
      }
    }
  }
  return EN_DOW[i];
}

export function englishWeekday(date: Date): string {
  return EN_DOW[date.getDay()];
}

function formatSingle(ts: Timestamp): string {
  const [o, c] = ts.active ? ['<', '>'] : ['[', ']'];
  let s = o + ts.date;
  if (ts.weekday !== null) s += ' ' + weekdayFor(ts.date, ts.weekday);
  if (ts.start) s += ' ' + ts.start + (ts.end ? '-' + ts.end : '');
  for (const ck of ts.cookies) s += ' ' + ck;
  return s + c;
}

/** Serialize TS keeping the original style (weekday presence/language, cookies). */
export function formatTimestamp(ts: Timestamp): string {
  return formatSingle(ts) + (ts.rangeEnd ? '--' + formatSingle(ts.rangeEnd) : '');
}

/** Replace the repeater cookie of TS with REP (or drop it), keeping warnings. */
export function withRepeater(ts: Timestamp, rep: string | null): Timestamp {
  const rest = ts.cookies.filter((c) => !/^(\.\+|\+\+|\+)\d+[hdwmy]$/.test(c));
  const cookies = rep ? [rep, ...rest] : rest;
  return { ...ts, cookies, repeater: parseCookies(cookies.join(' ')).repeater };
}

export function repeaterString(ts: Timestamp | null): string {
  if (!ts) return '';
  return ts.cookies.find((c) => /^(\.\+|\+\+|\+)\d+[hdwmy]$/.test(c)) ?? '';
}

export function warningString(ts: Timestamp | null): string {
  if (!ts) return '';
  return ts.cookies.find((c) => /^--?\d+[hdwmy]$/.test(c)) ?? '';
}

export function dateFromYmd(s: string): Date {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, m - 1, d);
}

export function ymd(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

export function hhmm(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

export function minutes(t: string): number {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
}

export function fromMinutes(n: number): string {
  const c = Math.max(0, Math.min(24 * 60 - 1, n));
  return `${pad2(Math.floor(c / 60))}:${pad2(c % 60)}`;
}
