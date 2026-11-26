// Capture entries appended to inbox-mobile.org.

import { englishWeekday, hhmm, ymd } from './timestamp';

export type TitleMode = 'firstLine' | 'timestamp';

export interface CaptureTemplate {
  id: string;
  label: string;
  tag: string;
  title: TitleMode;
  icon?: string;
  placeholder?: string;
}

export interface CaptureResult {
  /** Entry text ending with "\n", or null when the input is not valid. */
  entry: string | null;
  /** True when some body lines were shifted to avoid creating headlines. */
  escaped: boolean;
}

/** Shift body lines that would start a headline ("* ", "** ") by one space. */
export function escapeBody(lines: string[]): { lines: string[]; escaped: boolean } {
  let escaped = false;
  const out = lines.map((l) => {
    if (/^\*+[ \t]/.test(l) || /^\*+$/.test(l)) {
      escaped = true;
      return ' ' + l;
    }
    return l;
  });
  return { lines: out, escaped };
}

function trimTrailingBlank(lines: string[]): string[] {
  let e = lines.length;
  while (e > 0 && lines[e - 1].trim() === '') e--;
  return lines.slice(0, e);
}

export function createdStamp(now: Date): string {
  return `[${ymd(now)} ${englishWeekday(now)} ${hhmm(now)}]`;
}

/** Build the inbox entry for TEMPLATE from the user's TEXT at time NOW. */
export function buildCapture(template: CaptureTemplate, text: string, now: Date): CaptureResult {
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const tags = `  :${template.tag}:`;
  if (template.title === 'timestamp') {
    // Journal: the pipeline keeps only the body, so all text goes there.
    const body = trimTrailingBlank(lines);
    while (body.length && body[0].trim() === '') body.shift();
    if (!body.length) return { entry: null, escaped: false };
    const esc = escapeBody(body);
    const head = `* ${ymd(now)} ${hhmm(now)}${tags}`;
    return { entry: [head, ...esc.lines].join('\n') + '\n', escaped: esc.escaped };
  }
  const title = lines[0].trim();
  if (!title) return { entry: null, escaped: false };
  const rest = trimTrailingBlank(lines.slice(1));
  const esc = escapeBody(rest);
  const out = [`* ${title}${tags}`, ':PROPERTIES:', `:CREATED:  ${createdStamp(now)}`, ':END:', ...esc.lines];
  return { entry: out.join('\n') + '\n', escaped: esc.escaped };
}

/** Append ENTRY (ending with "\n") to TEXT, adding a newline separator when needed. */
export function appendEntry(text: string, entry: string): string {
  const sep = text === '' || text.endsWith('\n') ? '' : '\n';
  return text + sep + entry;
}
