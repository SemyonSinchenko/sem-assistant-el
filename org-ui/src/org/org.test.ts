import { describe, expect, it } from 'vitest';
import { appendEntry, buildCapture, type CaptureTemplate } from './capture';
import { applyHeadlineEdit, buildPlanningLine, diffLines, EditError, relocateHeadline, sensitiveBalanced } from './edit';
import { bodyText, parseOrg, serialize } from './parse';
import { occurrences } from './repeat';
import { findTimestamps, formatTimestamp, parseTimestamp, withRepeater } from './timestamp';

const FIXTURES: Record<string, string> = {
  simple: '* TODO Task :work:\nSCHEDULED: <2026-11-26 Thu>\nbody\n',
  crlf: '* TODO A\r\nSCHEDULED: <2026-11-26 Thu>\r\nline\r\n* B\r\n',
  noFinalNewline: '* A\nbody without newline',
  tabs: '*\tTabbed\t:x:\n\tindented body\n',
  blankBetween: '* A\n\n\n* B\n\n',
  unicode: '* Привет мир 🌍 :тег:\nтекст — «кавычки»\n',
  emptyTitle: '* \n** \nx\n',
  tagsNoSpace: '* Title:tag:\n',
  customTodo: '#+TODO: OPEN WIP | CLOSED\n* OPEN Thing\n* WIP Other\n* CLOSED Old\n',
  sensitive: '* A\n#+begin_sensitive\nsecret\n#+end_sensitive\n',
  srcBlock: '* Code\n#+begin_src org\n* not a headline\n** neither\n#+end_src\n* Real\n',
  drawers: '* A\n:PROPERTIES:\n:ID: 123\n:END:\n:LOGBOOK:\nCLOCK: [2026-11-26 Thu 10:00]\n:END:\nbody\n',
  plannerStyle: '* TODO Plan\nSCHEDULED: <2026-11-26 10:00-11:30>\n:PROPERTIES:\n:ID: abc\n:END:\n',
  empty: '',
  onlyNewline: '\n',
};

describe('round-trip', () => {
  for (const [name, text] of Object.entries(FIXTURES)) {
    it(name, () => {
      expect(serialize(parseOrg(text))).toBe(text);
    });
  }
});

describe('parser', () => {
  it('ignores headline-like lines inside src blocks', () => {
    const f = parseOrg(FIXTURES.srcBlock);
    expect(f.headlines.map((h) => h.title)).toEqual(['Code', 'Real']);
  });

  it('does not let an unterminated block swallow headlines', () => {
    const f = parseOrg('* A\n#+begin_src\n* B\n');
    expect(f.headlines.map((h) => h.title)).toEqual(['A', 'B']);
  });

  it('reads custom TODO keywords', () => {
    const f = parseOrg(FIXTURES.customTodo);
    expect(f.todo).toEqual({ active: ['OPEN', 'WIP'], done: ['CLOSED'] });
    expect(f.headlines.map((h) => h.keyword)).toEqual(['OPEN', 'WIP', 'CLOSED']);
  });

  it('parses keyword, priority, title, tags', () => {
    const f = parseOrg('* NEXT [#A] Do it  :a:b:\n');
    const h = f.headlines[0];
    expect([h.keyword, h.priority, h.title, h.tags]).toEqual(['NEXT', 'A', 'Do it', ['a', 'b']]);
  });

  it('inherits tags from parents and FILETAGS', () => {
    const f = parseOrg('#+FILETAGS: :f:\n* P :p:\n** C :c:\n');
    expect(f.headlines[1].allTags.sort()).toEqual(['c', 'f', 'p']);
    expect(f.headlines[1].inheritedTags.sort()).toEqual(['f', 'p']);
  });

  it('finds planning, properties and body range', () => {
    const f = parseOrg(FIXTURES.drawers);
    const h = f.headlines[0];
    expect(h.id).toBe('123');
    expect(bodyText(f, h)).toBe('body');
  });

  it('reads planner-style timestamps without weekday', () => {
    const h = parseOrg(FIXTURES.plannerStyle).headlines[0];
    expect(h.planning.scheduled).toMatchObject({ date: '2026-11-26', weekday: null, start: '10:00', end: '11:30' });
  });

  it('reads a legacy planning line placed after the drawer', () => {
    const h = parseOrg('* TODO X\n:PROPERTIES:\n:ID: 1\n:END:\nSCHEDULED: <2026-11-27 Fri>\nbody\n').headlines[0];
    expect(h.planning.scheduled?.date).toBe('2026-11-27');
    expect(h.bodyStart).toBe(5);
  });
});

describe('timestamps', () => {
  const all = [
    '<2026-11-26>',
    '<2026-11-26 Thu>',
    '<2026-11-26 Thu 10:00>',
    '<2026-11-26 10:00-11:30>',
    '<2026-11-26 Thu 10:00-11:30 +1w>',
    '<2026-11-26 Thu .+1d>',
    '<2026-11-26 Thu ++1w>',
    '<2026-11-26 Thu +1w -2d>',
    '<2026-11-26 Thu 10:00>--<2026-11-28 Sat 12:00>',
    '[2026-11-26 Thu 12:48]',
    '<2026-11-26 чт>',
  ];
  for (const s of all) {
    it(`round-trips ${s}`, () => {
      const ts = parseTimestamp(s);
      expect(ts).not.toBeNull();
      expect(formatTimestamp(ts!)).toBe(s);
    });
  }

  it('keeps weekday style when the date changes', () => {
    const noDow = parseTimestamp('<2026-11-26 10:00-11:30>')!;
    expect(formatTimestamp({ ...noDow, date: '2026-11-27' })).toBe('<2026-11-27 10:00-11:30>');
    const ru = parseTimestamp('<2026-11-26 чт>')!;
    expect(formatTimestamp({ ...ru, date: '2026-11-27' })).toBe('<2026-11-27 пт>');
    const en = parseTimestamp('<2026-11-26 Thu>')!;
    expect(formatTimestamp({ ...en, date: '2026-11-30' })).toBe('<2026-11-30 Mon>');
  });

  it('replaces the repeater and keeps the warning', () => {
    const ts = parseTimestamp('<2026-11-26 Thu +1w -2d>')!;
    expect(formatTimestamp(withRepeater(ts, '+1m'))).toBe('<2026-11-26 Thu +1m -2d>');
    expect(formatTimestamp(withRepeater(ts, null))).toBe('<2026-11-26 Thu -2d>');
  });

  it('distinguishes active and inactive', () => {
    const f = findTimestamps('a <2026-01-01> b [2026-01-02]');
    expect(f.map((x) => x.ts.active)).toEqual([true, false]);
  });
});

describe('repeaters', () => {
  const ts = (s: string) => parseTimestamp(s)!;
  it('+1w', () => {
    expect(occurrences(ts('<2026-11-02 Mon +1w>'), '2026-11-01', '2026-11-30')).toEqual([
      '2026-11-02',
      '2026-11-09',
      '2026-11-16',
      '2026-11-23',
      '2026-11-30',
    ]);
  });
  it('+1m on the 31st clamps to month end and comes back', () => {
    expect(occurrences(ts('<2026-01-31 Sat +1m>'), '2026-01-01', '2026-04-30')).toEqual([
      '2026-01-31',
      '2026-02-28',
      '2026-03-31',
      '2026-04-30',
    ]);
  });
  it('.+1d and ++1w expand from the base date', () => {
    expect(occurrences(ts('<2026-11-28 Sat .+1d>'), '2026-11-26', '2026-11-30')).toEqual([
      '2026-11-28',
      '2026-11-29',
      '2026-11-30',
    ]);
    expect(occurrences(ts('<2026-11-01 Sun ++1w>'), '2026-11-10', '2026-11-20')).toEqual(['2026-11-15']);
  });
  it('never before the base date and bounded', () => {
    expect(occurrences(ts('<2026-12-01 Tue +1d>'), '2026-11-01', '2026-11-30')).toEqual([]);
    expect(occurrences(ts('<2020-01-01 Wed +1d>'), '2020-01-01', '2030-01-01').length).toBe(1000);
  });
});

describe('minimal diff edits', () => {
  const changedLines = (a: string, b: string) => diffLines(a.split('\n'), b.split('\n')).filter((d) => d.kind !== 'same');

  it('changing SCHEDULED changes exactly one line', () => {
    const text = '* TODO A :x:\nSCHEDULED: <2026-11-26 Thu 10:00> DEADLINE: <2026-11-30 Mon>\n:PROPERTIES:\n:ID: 1\n:END:\nbody\n* B\n';
    const f = parseOrg(text);
    const h = f.headlines[0];
    const out = applyHeadlineEdit(f, h, { scheduled: { ...h.planning.scheduled!, date: '2026-11-27' } });
    expect(out).toBe(text.replace('<2026-11-26 Thu 10:00>', '<2026-11-27 Fri 10:00>'));
    expect(changedLines(text, out).length).toBe(2);
  });

  it('changing tags changes only the headline line', () => {
    const text = '* TODO A    :x:\nbody\n';
    const f = parseOrg(text);
    const out = applyHeadlineEdit(f, f.headlines[0], { tags: ['x', 'y'] });
    expect(out).toBe('* TODO A    :x:y:\nbody\n');
  });

  it('editing the body changes only body lines and keeps drawers', () => {
    const text = '* A\n:PROPERTIES:\n:ID: 1\n:END:\nold\n\n* B\n';
    const f = parseOrg(text);
    const out = applyHeadlineEdit(f, f.headlines[0], { body: 'new\nlines' });
    expect(out).toBe('* A\n:PROPERTIES:\n:ID: 1\n:END:\nnew\nlines\n\n* B\n');
  });

  it('keeps CRLF and a missing final newline', () => {
    const crlf = '* A\r\nold\r\n* B\r\n';
    const f = parseOrg(crlf);
    expect(applyHeadlineEdit(f, f.headlines[0], { body: 'new\nmore' })).toBe('* A\r\nnew\r\nmore\r\n* B\r\n');
    const nofinal = '* A\nold';
    const g = parseOrg(nofinal);
    expect(applyHeadlineEdit(g, g.headlines[0], { body: 'n1\nn2' })).toBe('* A\nn1\nn2');
    expect(applyHeadlineEdit(g, g.headlines[0], { body: '' })).toBe('* A');
  });

  it('creates the planning line right after the headline and removes it', () => {
    const text = '* TODO A\n:PROPERTIES:\n:ID: 1\n:END:\n';
    const f = parseOrg(text);
    const ts = parseTimestamp('<2026-11-26 Thu>')!;
    const added = applyHeadlineEdit(f, f.headlines[0], { scheduled: ts });
    expect(added).toBe('* TODO A\nSCHEDULED: <2026-11-26 Thu>\n:PROPERTIES:\n:ID: 1\n:END:\n');
    const g = parseOrg(added);
    expect(applyHeadlineEdit(g, g.headlines[0], { scheduled: null })).toBe(text);
  });

  it('planning line keeps key order and CLOSED', () => {
    expect(buildPlanningLine('DEADLINE: <2026-11-30 Mon> SCHEDULED: <2026-11-26 Thu>', { deadline: null })).toBe(
      'SCHEDULED: <2026-11-26 Thu>',
    );
    expect(buildPlanningLine('CLOSED: [2026-11-26 Thu 10:00] SCHEDULED: <2026-11-26 Thu>', { scheduled: null })).toBe(
      'CLOSED: [2026-11-26 Thu 10:00]',
    );
  });

  it('inserts planning and body together in the right order', () => {
    const f = parseOrg('* TODO A\n* B\n');
    const out = applyHeadlineEdit(f, f.headlines[0], { scheduled: parseTimestamp('<2026-11-26>')!, body: 'text' });
    expect(out).toBe('* TODO A\nSCHEDULED: <2026-11-26>\ntext\n* B\n');
  });

  it('refuses DONE for repeating entries', () => {
    const f = parseOrg('* TODO R\nSCHEDULED: <2026-11-26 Thu +1w>\n');
    expect(() => applyHeadlineEdit(f, f.headlines[0], { keyword: 'DONE' })).toThrow(EditError);
    expect(() => applyHeadlineEdit(f, f.headlines[0], { keyword: 'NEXT' })).not.toThrow();
  });

  it('refuses unbalanced sensitive blocks', () => {
    expect(sensitiveBalanced('#+begin_sensitive\nx\n#+end_sensitive')).toBe(true);
    expect(sensitiveBalanced('#+begin_sensitive\nx')).toBe(false);
    const f = parseOrg('* A\nbody\n');
    expect(() => applyHeadlineEdit(f, f.headlines[0], { body: '#+BEGIN_SENSITIVE\nx' })).toThrow(EditError);
  });

  it('relocates a headline by ID, by line, by unique text', () => {
    const f = parseOrg('* New\n* A\n:PROPERTIES:\n:ID: 7\n:END:\n* B\n');
    expect(relocateHeadline(f, { id: '7', line: 0, lineText: '* A' })?.line).toBe(1);
    expect(relocateHeadline(f, { id: null, line: 0, lineText: '* B' })?.line).toBe(5);
    expect(relocateHeadline(f, { id: null, line: 0, lineText: '* C' })).toBeNull();
  });
});

describe('capture', () => {
  const now = new Date(2026, 10, 26, 12, 48);
  const tpl = (id: string, title: 'firstLine' | 'timestamp'): CaptureTemplate => ({ id, label: id, tag: id, title });

  it('link', () => {
    expect(buildCapture(tpl('link', 'firstLine'), 'https://orgmode.org/\nперечитать\n\n', now).entry).toBe(
      '* https://orgmode.org/  :link:\n:PROPERTIES:\n:CREATED:  [2026-11-26 Thu 12:48]\n:END:\nперечитать\n',
    );
  });

  it('task without body', () => {
    expect(buildCapture(tpl('task', 'firstLine'), '  позвонить бухгалтеру завтра !  ', now).entry).toBe(
      '* позвонить бухгалтеру завтра !  :task:\n:PROPERTIES:\n:CREATED:  [2026-11-26 Thu 12:48]\n:END:\n',
    );
  });

  it('journal puts all text into the body', () => {
    expect(buildCapture(tpl('journal', 'timestamp'), 'Долго гулял\nветер сильный', now).entry).toBe(
      '* 2026-11-26 12:48  :journal:\nДолго гулял\nветер сильный\n',
    );
  });

  it('escapes body lines that look like headlines', () => {
    const r = buildCapture(tpl('task', 'firstLine'), 'title\n* item\n** sub', now);
    expect(r.escaped).toBe(true);
    expect(r.entry).toContain('\n * item\n ** sub\n');
  });

  it('rejects empty input', () => {
    expect(buildCapture(tpl('task', 'firstLine'), '\nbody', now).entry).toBeNull();
    expect(buildCapture(tpl('journal', 'timestamp'), '  \n ', now).entry).toBeNull();
  });

  it('appends with a separator only when needed', () => {
    expect(appendEntry('', 'x\n')).toBe('x\n');
    expect(appendEntry('a\n', 'x\n')).toBe('a\nx\n');
    expect(appendEntry('a', 'x\n')).toBe('a\nx\n');
  });
});
