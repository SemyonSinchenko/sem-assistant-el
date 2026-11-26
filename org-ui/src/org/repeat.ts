// Expansion of repeating timestamps into occurrences within a visible range.

import { dateFromYmd, ymd, type Timestamp } from './timestamp';

export const MAX_OCCURRENCES = 1000;

function addMonthsClamped(base: Date, months: number): Date {
  const y = base.getFullYear();
  const m = base.getMonth() + months;
  const last = new Date(y, m + 1, 0).getDate();
  return new Date(y, m, Math.min(base.getDate(), last));
}

/** Date of the K-th occurrence after BASE (computed from the base, not cumulatively). */
function nth(base: Date, n: number, unit: string, k: number): Date {
  const step = n * k;
  switch (unit) {
    case 'h':
    case 'd':
      // hourly repeaters are shown once per day
      return new Date(base.getFullYear(), base.getMonth(), base.getDate() + (unit === 'd' ? step : Math.floor(step / 24)));
    case 'w':
      return new Date(base.getFullYear(), base.getMonth(), base.getDate() + 7 * step);
    case 'm':
      return addMonthsClamped(base, step);
    default:
      return addMonthsClamped(base, 12 * step);
  }
}

/**
 * Return YYYY-MM-DD dates of TS that fall within [FROM, TO] (inclusive dates).
 * Repeaters expand forward from the base date, never before it.
 */
export function occurrences(ts: Timestamp, from: string, to: string): string[] {
  const out: string[] = [];
  const rep = ts.repeater;
  if (!rep || rep.n <= 0) {
    if (ts.date >= from && ts.date <= to) out.push(ts.date);
    return out;
  }
  const base = dateFromYmd(ts.date);
  let last = '';
  for (let k = 0; k < 100000 && out.length < MAX_OCCURRENCES; k++) {
    const d = ymd(nth(base, rep.n, rep.unit, k));
    if (d > to) break;
    if (d !== last && d >= from) out.push(d);
    last = d;
  }
  return out;
}
