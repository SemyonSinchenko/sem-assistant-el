// Small presentational pieces: TODO badges, tag chips, planning chips.

import type { Headline, OrgFile } from '../org/parse';
import { dateFromYmd, repeaterString, type Timestamp } from '../org/timestamp';

const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function today(): Date {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

export function daysFromToday(date: string): number {
  return Math.round((dateFromYmd(date).getTime() - today().getTime()) / 864e5);
}

/** Human-readable date like "today 14:00–16:00" or "Fri 28 Nov". */
export function humanTs(ts: Timestamp): string {
  const n = daysFromToday(ts.date);
  const d = dateFromYmd(ts.date);
  let s =
    n === 0 ? 'today' : n === 1 ? 'tomorrow' : n === -1 ? 'yesterday' : `${DOW[d.getDay()]} ${d.getDate()} ${MON[d.getMonth()]}`;
  if (d.getFullYear() !== new Date().getFullYear()) s += ' ' + d.getFullYear();
  if (ts.start) s += ' ' + ts.start + (ts.end ? '–' + ts.end : '');
  return s;
}

export function Keyword({ kw, file }: { kw: string | null; file: OrgFile }) {
  if (!kw) return null;
  const done = file.todo.done.includes(kw);
  const cls = done ? 'done' : ['TODO', 'NEXT', 'WAITING'].includes(kw) ? kw : 'other';
  return <span className={`kw ${cls}`}>{kw}</span>;
}

export function Priority({ p }: { p: string | null }) {
  return p ? <span className="prio">#{p}</span> : null;
}

export function Tags({ h }: { h: Headline }) {
  if (!h.tags.length && !h.inheritedTags.length) return null;
  return (
    <>
      {h.tags.map((t) => (
        <span key={t} className="tag">
          {t}
        </span>
      ))}
      {h.inheritedTags.map((t) => (
        <span key={'i' + t} className="tag inh" title="inherited">
          {t}
        </span>
      ))}
    </>
  );
}

export function PlanningChips({ h, file }: { h: Headline; file: OrgFile }) {
  const { scheduled, deadline } = h.planning;
  if (!scheduled && !deadline) return null;
  const done = !!h.keyword && file.todo.done.includes(h.keyword);
  const late = deadline && !done && daysFromToday(deadline.date) <= 2;
  return (
    <div className="pls">
      {scheduled && (
        <span className="pl">
          SCHEDULED <b>{humanTs(scheduled)}</b>
          {scheduled.repeater && <> ↻ {repeaterString(scheduled)}</>}
        </span>
      )}
      {deadline && (
        <span className={'pl' + (late ? ' dlx' : '')}>
          DEADLINE <b>{humanTs(deadline)}</b>
          {deadline.repeater && <> ↻ {repeaterString(deadline)}</>}
        </span>
      )}
    </div>
  );
}
