// Calendar model: filter state and conversion of Org entries into calendar events.

import type { Config } from '../config';
import type { Headline, OrgFile } from '../org/parse';
import { occurrences } from '../org/repeat';
import { dateFromYmd, fromMinutes, minutes, warningString, ymd, type Timestamp } from '../org/timestamp';

export interface Filter {
  /** null = all files */
  files: string[] | null;
  include: string[];
  exclude: string[];
  /** null = all non-done keywords plus entries without keyword */
  states: string[] | null;
  showDone: boolean;
  showDeadline: boolean;
  showBody: boolean;
  showUntimed: boolean;
}

export function defaultFilter(config: Config): Filter {
  return {
    files: null,
    include: [],
    exclude: [],
    states: null,
    showDone: false,
    showDeadline: true,
    showBody: config.calendar.bodyTimestamps,
    showUntimed: true,
  };
}

export const NO_KEYWORD = '—';

export function filterCount(f: Filter, d: Filter): number {
  return (
    (f.files ? 1 : 0) +
    f.include.length +
    f.exclude.length +
    (f.states ? 1 : 0) +
    (f.showDone !== d.showDone ? 1 : 0) +
    (f.showDeadline !== d.showDeadline ? 1 : 0) +
    (f.showBody !== d.showBody ? 1 : 0) +
    (f.showUntimed !== d.showUntimed ? 1 : 0)
  );
}

export function filterQuery(f: Filter): string {
  const p: string[] = [];
  if (f.files) p.push(...f.files.map((x) => 'file:' + x));
  p.push(...f.include.map((t) => '+' + t));
  p.push(...f.exclude.map((t) => '-' + t));
  if (f.states) p.push('state:' + (f.states.join(',') || '∅'));
  if (!f.showDone) p.push('-DONE');
  if (!f.showDeadline) p.push('-deadline');
  if (f.showBody) p.push('+body');
  if (!f.showUntimed) p.push('-untimed');
  return p.join(' ') || 'all';
}

export function passes(f: Filter, path: string, org: OrgFile, h: Headline): boolean {
  if (f.files && !f.files.includes(path)) return false;
  const done = !!h.keyword && org.todo.done.includes(h.keyword);
  if (done && !f.showDone) return false;
  if (f.states && !f.states.includes(h.keyword ?? NO_KEYWORD) && !done) return false;
  if (f.include.length && !h.allTags.some((t) => f.include.includes(t))) return false;
  if (h.allTags.some((t) => f.exclude.includes(t))) return false;
  return true;
}

export type EventKind = 'scheduled' | 'deadline' | 'title' | 'body' | 'warning';

export interface CalEvent {
  id: string;
  title: string;
  start: string;
  end?: string;
  allDay: boolean;
  path: string;
  line: number;
  kind: EventKind;
  repeating: boolean;
  done: boolean;
  draggable: boolean;
  color: string;
  display?: 'background';
}

function addDays(date: string, n: number): string {
  const d = dateFromYmd(date);
  d.setDate(d.getDate() + n);
  return ymd(d);
}

function warningDays(ts: Timestamp): number {
  const w = warningString(ts).match(/^--?(\d+)([hdwmy])$/);
  if (!w) return 0;
  const n = Number(w[1]);
  return w[2] === 'w' ? n * 7 : w[2] === 'm' ? n * 30 : w[2] === 'y' ? n * 365 : w[2] === 'd' ? n : 0;
}

/** Events of TS occurring within [FROM, TO]. */
function tsEvents(ts: Timestamp, from: string, to: string, base: Omit<CalEvent, 'id' | 'start' | 'end' | 'allDay'>, idp: string): CalEvent[] {
  const out: CalEvent[] = [];
  const dates = ts.repeater ? occurrences(ts, from, to) : ts.rangeEnd ? (ts.date <= to && ts.rangeEnd.date >= from ? [ts.date] : []) : occurrences(ts, from, to);
  for (const d of dates) {
    const id = `${idp}:${d}`;
    if (ts.rangeEnd && !ts.repeater) {
      out.push({ ...base, id, start: d, end: addDays(ts.rangeEnd.date, 1), allDay: true });
    } else if (ts.start) {
      let end: string | undefined;
      if (ts.end && minutes(ts.end) > minutes(ts.start)) end = `${d}T${ts.end}`;
      else end = `${d}T${fromMinutes(Math.min(minutes(ts.start) + 60, 24 * 60 - 1))}`;
      out.push({ ...base, id, start: `${d}T${ts.start}`, end, allDay: false });
    } else {
      out.push({ ...base, id, start: d, allDay: true });
    }
  }
  return out;
}

export function buildEvents(
  files: { path: string; org: OrgFile; color: string; readOnly: boolean; noDrag: boolean }[],
  filter: Filter,
  from: string,
  to: string,
  titleOf: (h: Headline) => string,
): CalEvent[] {
  const out: CalEvent[] = [];
  for (const { path, org, color, readOnly, noDrag } of files) {
    for (const h of org.headlines) {
      if (!passes(filter, path, org, h)) continue;
      const done = !!h.keyword && org.todo.done.includes(h.keyword);
      const title = titleOf(h);
      const base = { path, line: h.line, done, color, title };
      const push = (evs: CalEvent[]) => {
        for (const e of evs) if (filter.showUntimed || !e.allDay || e.kind === 'warning') out.push(e);
      };
      const s = h.planning.scheduled;
      if (s) {
        const repeating = !!s.repeater;
        push(
          tsEvents(s, from, to, { ...base, kind: 'scheduled', repeating, draggable: !repeating && !readOnly && !noDrag && !s.rangeEnd }, `${path}:${h.line}:s`),
        );
      }
      const d = h.planning.deadline;
      if (d && filter.showDeadline) {
        push(tsEvents(d, from, to, { ...base, kind: 'deadline', repeating: !!d.repeater, draggable: false }, `${path}:${h.line}:d`));
        const wd = warningDays(d);
        if (wd > 0 && !done && !d.repeater && d.date >= from && addDays(d.date, -wd) <= to) {
          out.push({
            ...base,
            id: `${path}:${h.line}:w`,
            kind: 'warning',
            repeating: false,
            draggable: false,
            start: addDays(d.date, -wd),
            end: d.date,
            allDay: true,
            display: 'background',
          });
        }
      }
      h.titleTimestamps.forEach((ts, i) =>
        push(tsEvents(ts, from, to, { ...base, kind: 'title', repeating: !!ts.repeater, draggable: false }, `${path}:${h.line}:t${i}`)),
      );
      if (filter.showBody)
        h.bodyTimestamps.forEach((ts, i) =>
          push(tsEvents(ts, from, to, { ...base, kind: 'body', repeating: !!ts.repeater, draggable: false }, `${path}:${h.line}:b${i}`)),
        );
    }
  }
  return out;
}

export function allTagsOf(orgs: OrgFile[]): string[] {
  const s = new Set<string>();
  for (const o of orgs) for (const h of o.headlines) h.allTags.forEach((t) => s.add(t));
  return [...s].sort();
}
