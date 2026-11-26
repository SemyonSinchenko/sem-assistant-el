// Minimal line edits of a single headline: headline line, planning line, body.
// Everything else in the file stays byte-identical.

import {
  editableBodyRange,
  hasRepeater,
  isDoneKeyword,
  joinLines,
  parseHeadlineLine,
  type Headline,
  type OrgFile,
} from './parse';
import { findTimestamps, formatTimestamp, type Timestamp } from './timestamp';

export interface HeadlineChanges {
  keyword?: string | null;
  priority?: string | null;
  title?: string;
  tags?: string[];
  scheduled?: Timestamp | null;
  deadline?: Timestamp | null;
  body?: string;
}

export class EditError extends Error {}

/** Return the dominant line terminator of FILE. */
export function fileEol(file: OrgFile): string {
  return file.eols.some((e) => e === '\r\n') && !file.eols.some((e) => e === '\n') ? '\r\n' : '\n';
}

/** Check that #+begin_sensitive / #+end_sensitive are properly paired in TEXT. */
export function sensitiveBalanced(text: string): boolean {
  let open = false;
  for (const l of text.split(/\r?\n/)) {
    if (/^[ \t]*#\+begin_sensitive\b/i.test(l)) {
      if (open) return false;
      open = true;
    } else if (/^[ \t]*#\+end_sensitive\b/i.test(l)) {
      if (!open) return false;
      open = false;
    }
  }
  return !open;
}

/** Rebuild the headline line; returns the original line when nothing changed. */
export function buildHeadlineLine(original: string, file: OrgFile, ch: HeadlineChanges): string {
  const kws = [...file.todo.active, ...file.todo.done];
  const p = parseHeadlineLine(original, kws)!;
  const keyword = ch.keyword !== undefined ? ch.keyword : p.keyword;
  const priority = ch.priority !== undefined ? ch.priority : p.priority;
  const title = ch.title !== undefined ? ch.title.replace(/[\r\n]+/g, ' ') : p.title;
  const tags = ch.tags !== undefined ? ch.tags : p.tags;
  const same =
    keyword === p.keyword &&
    priority === p.priority &&
    title === p.title &&
    tags.length === p.tags.length &&
    tags.every((t, i) => t === p.tags[i]);
  if (same) return original;

  // keep the original whitespace before the tags if there was any
  const tm = original.match(/([ \t]+):(?:[^\s:]+:)+[ \t]*$/);
  const tagSep = tm ? tm[1] : '  ';
  let s = p.stars + ' ';
  if (keyword) s += keyword + ' ';
  if (priority) s += `[#${priority}] `;
  s += title;
  if (tags.length) s += (title ? tagSep : '') + ':' + tags.join(':') + ':';
  return s.replace(/[ \t]+$/, '');
}

type PlanKey = 'SCHEDULED' | 'DEADLINE';

/** Apply scheduled/deadline changes to a planning line; null means "no planning line". */
export function buildPlanningLine(
  original: string | null,
  ch: { scheduled?: Timestamp | null; deadline?: Timestamp | null },
): string | null {
  let line = original ?? '';
  const set = (key: PlanKey, ts: Timestamp | null | undefined) => {
    if (ts === undefined) return;
    const re = new RegExp(`(${key}:[ \\t]*)`);
    const m = line.match(re);
    if (m && m.index !== undefined) {
      const after = m.index + m[0].length;
      const found = findTimestamps(line.slice(after));
      const old = found.length && found[0].index === 0 ? found[0] : null;
      const oldLen = old ? old.length : 0;
      if (ts === null) {
        // remove "KEY: <ts>" together with the separating whitespace
        let start = m.index;
        let end = after + oldLen;
        const tail = line.slice(end).match(/^[ \t]*/)![0];
        if (start === line.search(/\S/)) end += tail.length;
        else {
          const lead = line.slice(0, start).match(/[ \t]*$/)![0];
          start -= lead.length;
        }
        line = line.slice(0, start) + line.slice(end);
      } else {
        const next = formatTimestamp(ts);
        if (!old || old.raw !== next) line = line.slice(0, after) + next + line.slice(after + oldLen);
      }
    } else if (ts) {
      const add = `${key}: ${formatTimestamp(ts)}`;
      line = line.trim() ? line.replace(/[ \t]*$/, '') + ' ' + add : (line.match(/^[ \t]*/)![0] ?? '') + add;
    }
  };
  set('SCHEDULED', ch.scheduled);
  set('DEADLINE', ch.deadline);
  if (!/\b(SCHEDULED|DEADLINE|CLOSED):/.test(line)) return null;
  return line;
}

interface Splice {
  start: number;
  end: number;
  lines: string[];
}

/**
 * Apply CHANGES to headline H of FILE and return the new file text.
 * Only the headline line, the planning line and the body lines change.
 */
export function applyHeadlineEdit(file: OrgFile, h: Headline, changes: HeadlineChanges): string {
  const eol = fileEol(file);
  const newKw = changes.keyword !== undefined ? changes.keyword : h.keyword;
  if (newKw !== h.keyword && isDoneKeyword(file, newKw) && hasRepeater(h)) {
    throw new EditError('A repeating entry cannot be marked done from the UI');
  }
  if (changes.body !== undefined && !sensitiveBalanced(changes.body)) {
    throw new EditError('Unbalanced #+begin_sensitive / #+end_sensitive in the text');
  }
  if (changes.body !== undefined && changes.body.split(/\r?\n/).some((l) => /^\*+[ \t]/.test(l))) {
    throw new EditError('A body line starting with "* " would create a new headline');
  }

  const splices: Splice[] = [];
  const hl = buildHeadlineLine(file.lines[h.line], file, changes);
  if (hl !== file.lines[h.line]) splices.push({ start: h.line, end: h.line + 1, lines: [hl] });

  if (changes.scheduled !== undefined || changes.deadline !== undefined) {
    const orig = h.planningLine !== null ? file.lines[h.planningLine] : null;
    const next = buildPlanningLine(orig, { scheduled: changes.scheduled, deadline: changes.deadline });
    if (h.planningLine !== null) {
      if (next === null) splices.push({ start: h.planningLine, end: h.planningLine + 1, lines: [] });
      else if (next !== orig) splices.push({ start: h.planningLine, end: h.planningLine + 1, lines: [next] });
    } else if (next !== null) {
      splices.push({ start: h.line + 1, end: h.line + 1, lines: [next] });
    }
  }

  if (changes.body !== undefined) {
    const [s, e] = editableBodyRange(file, h);
    const oldBody = file.lines.slice(s, e).join('\n');
    const newBody = changes.body.replace(/\r\n/g, '\n').replace(/\s+$/, '');
    if (newBody !== oldBody) splices.push({ start: s, end: e, lines: newBody === '' ? [] : newBody.split('\n') });
  }

  if (!splices.length) return file.text;
  return applySplices(file, splices, eol);
}

/** Apply non-overlapping line splices (sorted or not) and rejoin with original terminators. */
function applySplices(file: OrgFile, splices: Splice[], eol: string): string {
  // later splices first; on ties the one pushed later (body) goes first so
  // that an inserted planning line ends up above an inserted body
  const sorted = splices
    .map((sp, order) => ({ ...sp, order }))
    .sort((a, b) => b.start - a.start || b.end - a.end || b.order - a.order);
  const lines = [...file.lines];
  const eols = [...file.eols];
  for (const sp of sorted) {
    const removedEols = eols.slice(sp.start, sp.end);
    const newEols = sp.lines.map(() => eol);
    if (sp.lines.length && removedEols.length) {
      // the last new line inherits the terminator of the last replaced line
      newEols[newEols.length - 1] = removedEols[removedEols.length - 1];
    } else if (sp.lines.length && sp.start === lines.length) {
      // appended after the last line of a file without trailing newline
      if (eols.length) eols[eols.length - 1] = eol;
      newEols[newEols.length - 1] = '';
    }
    if (!sp.lines.length && sp.end === lines.length && sp.start > 0) {
      // removing the tail: previous line takes over the final terminator
      eols[sp.start - 1] = eols[sp.end - 1];
    }
    lines.splice(sp.start, sp.end - sp.start, ...sp.lines);
    eols.splice(sp.start, sp.end - sp.start, ...newEols);
  }
  return joinLines(lines, eols);
}

/** Locate the headline that EDITOR_HL (from an older version) refers to in FRESH. */
export function relocateHeadline(
  fresh: OrgFile,
  old: { id: string | null; line: number; lineText: string },
): Headline | null {
  if (old.id) {
    const byId = fresh.headlines.find((h) => h.id === old.id);
    if (byId) return byId;
  }
  const atLine = fresh.headlines.find((h) => h.line === old.line && fresh.lines[h.line] === old.lineText);
  if (atLine) return atLine;
  const same = fresh.headlines.filter((h) => fresh.lines[h.line] === old.lineText);
  return same.length === 1 ? same[0] : null;
}

export interface DiffLine {
  kind: 'same' | 'del' | 'add';
  text: string;
}

/** Line diff of two small texts (LCS); used to show what an edit changes. */
export function diffLines(a: string[], b: string[]): DiffLine[] {
  const n = a.length;
  const m = b.length;
  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--)
    for (let j = m - 1; j >= 0; j--) dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const out: DiffLine[] = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      out.push({ kind: 'same', text: a[i] });
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) out.push({ kind: 'del', text: a[i++] });
    else out.push({ kind: 'add', text: b[j++] });
  }
  while (i < n) out.push({ kind: 'del', text: a[i++] });
  while (j < m) out.push({ kind: 'add', text: b[j++] });
  return out;
}
