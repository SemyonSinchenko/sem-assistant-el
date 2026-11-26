// Line-based Org parser. The file text is kept verbatim as lines + line
// terminators; the parser only builds an index of headlines over line ranges.

import { findTimestamps, type Timestamp } from './timestamp';

export interface TodoKeywords {
  active: string[];
  done: string[];
}

export interface Planning {
  scheduled: Timestamp | null;
  deadline: Timestamp | null;
  closed: Timestamp | null;
}

export interface Headline {
  /** Position in OrgFile.headlines. */
  index: number;
  /** Line number of the headline line. */
  line: number;
  level: number;
  keyword: string | null;
  priority: string | null;
  title: string;
  tags: string[];
  /** Own + ancestors + file tags, deduplicated. */
  allTags: string[];
  inheritedTags: string[];
  parent: number | null;
  planningLine: number | null;
  planning: Planning;
  /** [start, end) of the :PROPERTIES: drawer including its delimiters. */
  propertiesRange: [number, number] | null;
  properties: [string, string][];
  id: string | null;
  /** [start, end) of the body: after planning and leading drawers up to the next headline. */
  bodyStart: number;
  bodyEnd: number;
  /** End (exclusive) of the whole subtree. */
  subtreeEnd: number;
  /** Active timestamps in the title text. */
  titleTimestamps: Timestamp[];
  /** Active timestamps in body lines (outside drawers). */
  bodyTimestamps: Timestamp[];
}

export interface OrgFile {
  text: string;
  lines: string[];
  eols: string[];
  todo: TodoKeywords;
  fileTags: string[];
  headlines: Headline[];
}

export const DEFAULT_TODO: TodoKeywords = {
  active: ['TODO', 'NEXT', 'WAITING'],
  done: ['DONE', 'CANCELLED'],
};

/** Split TEXT into lines and their terminators so that join is byte-identical. */
export function splitLines(text: string): { lines: string[]; eols: string[] } {
  const parts = text.split(/(\r\n|\n)/);
  const lines: string[] = [];
  const eols: string[] = [];
  for (let i = 0; i < parts.length; i += 2) {
    lines.push(parts[i]);
    eols.push(parts[i + 1] ?? '');
  }
  return { lines, eols };
}

export function joinLines(lines: string[], eols: string[]): string {
  let s = '';
  for (let i = 0; i < lines.length; i++) s += lines[i] + (eols[i] ?? '');
  return s;
}

export function serialize(file: OrgFile): string {
  return joinLines(file.lines, file.eols);
}

const HEADLINE_RE = /^(\*+)[ \t]+(.*)$/;
const HEADLINE_EMPTY_RE = /^(\*+)[ \t]*$/;
const TAGS_RE = /^(.*?)(?:([ \t]+)(:(?:[^\s:]+:)+))?[ \t]*$/;
const PLANNING_RE = /^[ \t]*(?:(?:SCHEDULED|DEADLINE|CLOSED):[ \t]*[<[][^>\]\n]*[>\]][ \t]*)+$/;
const DRAWER_START_RE = /^[ \t]*:([A-Za-z0-9_-]+):[ \t]*$/;
const DRAWER_END_RE = /^[ \t]*:END:[ \t]*$/i;
const BLOCK_BEGIN_RE = /^[ \t]*#\+begin_(\S+)/i;
const BLOCK_END_RE = /^[ \t]*#\+end_(\S+)/i;

export function isHeadlineLine(line: string): boolean {
  return HEADLINE_RE.test(line) || HEADLINE_EMPTY_RE.test(line);
}

function parseTodoLine(rest: string, acc: TodoKeywords | null): TodoKeywords {
  const words = rest.trim().split(/\s+/).filter(Boolean).map((w) => w.replace(/\(.*\)$/, ''));
  const bar = words.indexOf('|');
  let active: string[];
  let done: string[];
  if (bar >= 0) {
    active = words.slice(0, bar);
    done = words.slice(bar + 1);
  } else {
    active = words.slice(0, -1);
    done = words.slice(-1);
  }
  const base = acc ?? { active: [], done: [] };
  return { active: [...base.active, ...active], done: [...base.done, ...done] };
}

function parseFileTags(rest: string): string[] {
  return rest
    .trim()
    .split(/[\s:]+/)
    .filter(Boolean);
}

export interface HeadlineParts {
  stars: string;
  keyword: string | null;
  priority: string | null;
  title: string;
  tags: string[];
}

export function parseHeadlineLine(line: string, keywords: string[]): HeadlineParts | null {
  let m = line.match(HEADLINE_RE);
  if (!m) {
    const e = line.match(HEADLINE_EMPTY_RE);
    if (!e) return null;
    return { stars: e[1], keyword: null, priority: null, title: '', tags: [] };
  }
  const stars = m[1];
  let rest = m[2];
  let keyword: string | null = null;
  const kw = rest.match(/^(\S+)(?:[ \t]+|$)/);
  if (kw && keywords.includes(kw[1])) {
    keyword = kw[1];
    rest = rest.slice(kw[0].length);
  }
  let priority: string | null = null;
  const pr = rest.match(/^\[#([A-Z0-9])\](?:[ \t]+|$)/);
  if (pr) {
    priority = pr[1];
    rest = rest.slice(pr[0].length);
  }
  const t = rest.match(TAGS_RE)!;
  let title = t[1];
  let tags: string[] = [];
  if (t[3]) {
    tags = t[3].split(':').filter(Boolean);
  } else if (/^:(?:[^\s:]+:)+$/.test(title.trim())) {
    // a headline that consists of tags only
    tags = title.trim().split(':').filter(Boolean);
    title = '';
  }
  return { stars, keyword, priority, title, tags };
}

function hasBlockEnd(lines: string[], from: number, name: string): boolean {
  for (let i = from; i < lines.length; i++) {
    const e = lines[i].match(BLOCK_END_RE);
    if (e && e[1].toLowerCase() === name) return true;
  }
  return false;
}

export function parseOrg(text: string, defaults: TodoKeywords = DEFAULT_TODO): OrgFile {
  const { lines, eols } = splitLines(text);

  // pass 1: in-buffer settings and headline positions (outside blocks)
  let todo: TodoKeywords | null = null;
  let fileTags: string[] = [];
  const hlLines: number[] = [];
  let block: string | null = null;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (block) {
      const e = l.match(BLOCK_END_RE);
      if (e && e[1].toLowerCase() === block) block = null;
      continue;
    }
    const b = l.match(BLOCK_BEGIN_RE);
    if (b && hasBlockEnd(lines, i + 1, b[1].toLowerCase())) {
      // an unterminated block must not swallow the rest of the file
      block = b[1].toLowerCase();
      continue;
    }
    const s = l.match(/^#\+(TODO|SEQ_TODO|TYP_TODO|FILETAGS):(.*)$/i);
    if (s) {
      if (s[1].toUpperCase() === 'FILETAGS') fileTags = parseFileTags(s[2]);
      else todo = parseTodoLine(s[2], todo);
      continue;
    }
    if (isHeadlineLine(l)) hlLines.push(i);
  }
  const keywords = todo ?? defaults;
  const allKw = [...keywords.active, ...keywords.done];

  // pass 2: headline details
  const headlines: Headline[] = [];
  const stack: Headline[] = [];
  for (let k = 0; k < hlLines.length; k++) {
    const line = hlLines[k];
    const next = k + 1 < hlLines.length ? hlLines[k + 1] : lines.length;
    const parts = parseHeadlineLine(lines[line], allKw)!;
    const level = parts.stars.length;
    while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
    const parent = stack.length ? stack[stack.length - 1] : null;

    let cur = line + 1;
    let planningLine: number | null = null;
    const planning: Planning = { scheduled: null, deadline: null, closed: null };
    const readPlanning = (i: number) => {
      planningLine = i;
      const txt = lines[i];
      for (const key of ['SCHEDULED', 'DEADLINE', 'CLOSED'] as const) {
        const idx = txt.indexOf(key + ':');
        if (idx < 0) continue;
        const found = findTimestamps(txt.slice(idx + key.length + 1));
        if (found.length) planning[key.toLowerCase() as keyof Planning] = found[0].ts;
      }
    };
    if (cur < next && PLANNING_RE.test(lines[cur])) {
      readPlanning(cur);
      cur++;
    }
    let propertiesRange: [number, number] | null = null;
    const properties: [string, string][] = [];
    // leading drawers (PROPERTIES first, then e.g. LOGBOOK) are never edited
    while (cur < next) {
      const d = lines[cur].match(DRAWER_START_RE);
      if (!d || d[1].toUpperCase() === 'END') break;
      let end = cur + 1;
      while (end < next && !DRAWER_END_RE.test(lines[end])) end++;
      if (end >= next) break; // unterminated drawer: treat as body
      if (d[1].toUpperCase() === 'PROPERTIES' && !propertiesRange) {
        propertiesRange = [cur, end + 1];
        for (let p = cur + 1; p < end; p++) {
          const pm = lines[p].match(/^[ \t]*:([^\s:]+):(?:[ \t]+(.*?))?[ \t]*$/);
          if (pm) properties.push([pm[1], pm[2] ?? '']);
        }
      }
      cur = end + 1;
      // legacy layout: planning line placed after the property drawer
      if (planningLine === null && cur < next && PLANNING_RE.test(lines[cur])) {
        readPlanning(cur);
        cur++;
      }
    }

    const ownTags = parts.tags;
    const inherited = [...(parent ? parent.allTags : fileTags)];
    const allTags = [...new Set([...ownTags, ...inherited])];
    const idProp = properties.find(([key]) => key.toUpperCase() === 'ID');

    const bodyTs: Timestamp[] = [];
    let inDrawer = false;
    for (let i = cur; i < next; i++) {
      if (DRAWER_START_RE.test(lines[i]) && !DRAWER_END_RE.test(lines[i])) inDrawer = true;
      else if (inDrawer && DRAWER_END_RE.test(lines[i])) inDrawer = false;
      else if (!inDrawer) for (const f of findTimestamps(lines[i])) if (f.ts.active) bodyTs.push(f.ts);
    }

    const h: Headline = {
      index: headlines.length,
      line,
      level,
      keyword: parts.keyword,
      priority: parts.priority,
      title: parts.title,
      tags: ownTags,
      allTags,
      inheritedTags: inherited.filter((t) => !ownTags.includes(t)),
      parent: parent ? parent.index : null,
      planningLine,
      planning,
      propertiesRange,
      properties,
      id: idProp ? idProp[1] : null,
      bodyStart: cur,
      bodyEnd: next,
      subtreeEnd: lines.length,
      titleTimestamps: findTimestamps(parts.title).filter((f) => f.ts.active).map((f) => f.ts),
      bodyTimestamps: bodyTs,
    };
    headlines.push(h);
    stack.push(h);
  }
  // subtree ends
  for (let i = 0; i < headlines.length; i++) {
    const h = headlines[i];
    let end = lines.length;
    for (let j = i + 1; j < headlines.length; j++) {
      if (headlines[j].level <= h.level) {
        end = headlines[j].line;
        break;
      }
    }
    h.subtreeEnd = end;
  }

  return { text, lines, eols, todo: keywords, fileTags, headlines };
}

export function isDoneKeyword(file: OrgFile, kw: string | null): boolean {
  return !!kw && file.todo.done.includes(kw);
}

export function hasRepeater(h: Headline): boolean {
  return !!(h.planning.scheduled?.repeater || h.planning.deadline?.repeater);
}

/** Text of the editable body (without trailing blank lines), joined with "\n". */
export function bodyText(file: OrgFile, h: Headline): string {
  const [s, e] = editableBodyRange(file, h);
  return file.lines.slice(s, e).join('\n');
}

/** [start, end) of body lines excluding trailing blank lines. */
export function editableBodyRange(file: OrgFile, h: Headline): [number, number] {
  let e = h.bodyEnd;
  while (e > h.bodyStart && file.lines[e - 1].trim() === '') e--;
  return [h.bodyStart, e];
}

/** Org source of the headline section (headline line up to the next headline). */
export function sectionSource(file: OrgFile, h: Headline): string {
  return joinLines(file.lines.slice(h.line, h.bodyEnd), file.eols.slice(h.line, h.bodyEnd)).replace(/\s+$/, '');
}

/** Ancestors of H from the root down. */
export function ancestors(file: OrgFile, h: Headline): Headline[] {
  const out: Headline[] = [];
  let p = h.parent;
  while (p !== null) {
    out.unshift(file.headlines[p]);
    p = file.headlines[p].parent;
  }
  return out;
}
