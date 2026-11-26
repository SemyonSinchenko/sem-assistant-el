// Write operations with optimistic locking on top of DavClient.

import { appendEntry } from '../org/capture';
import { applyHeadlineEdit, relocateHeadline, type HeadlineChanges } from '../org/edit';
import { parseOrg, type Headline, type TodoKeywords } from '../org/parse';
import { DavError, DavNetworkError, type DavClient } from './client';

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export type AppendResult = { ok: true; text: string } | { ok: false; retryable: boolean; error: string };

/** Append ENTRY to the end of PATH: GET → append → PUT If-Match; 412 → retry. */
export async function appendToFile(
  client: Pick<DavClient, 'get' | 'put'>,
  path: string,
  entry: string,
  delay: (ms: number) => Promise<void> = sleep,
): Promise<AppendResult> {
  for (let i = 0; i < 5; i++) {
    try {
      const cur = await client.get(path);
      const text = appendEntry(cur?.text ?? '', entry);
      await client.put(path, text, cur ? cur.etag : null);
      return { ok: true, text };
    } catch (e) {
      if (e instanceof DavError && e.status === 412) {
        await delay(200 * 2 ** i + Math.random() * 100);
        continue;
      }
      if (e instanceof DavNetworkError || (e instanceof DavError && e.status >= 500)) {
        return { ok: false, retryable: true, error: e.message };
      }
      // 401: credentials may be fixed later, keep the entry queued
      return { ok: false, retryable: e instanceof DavError && e.status === 401, error: (e as Error).message };
    }
  }
  return { ok: false, retryable: true, error: 'The file keeps changing (412), will retry later' };
}

export interface EditTarget {
  path: string;
  /** Headline as it was when the editor opened. */
  id: string | null;
  line: number;
  lineText: string;
  /** Lines of the headline section [line, bodyEnd) when the editor opened. */
  sectionLines: string[];
}

export type SaveResult =
  | { ok: true; text: string; etag: string | null }
  | { ok: false; conflict: true; serverSection: string | null }
  | { ok: false; conflict: false; error: string };

function sectionOf(lines: string[], h: Headline): string[] {
  return lines.slice(h.line, h.bodyEnd);
}

/**
 * Save CHANGES of TARGET: re-read the file, relocate the headline, ensure it
 * did not change on the server, apply the line edit, PUT with If-Match.
 * FORCE skips the "changed on the server" check (user chose to overwrite).
 */
export async function saveHeadline(
  client: Pick<DavClient, 'get' | 'put'>,
  target: EditTarget,
  changes: HeadlineChanges,
  todo: TodoKeywords,
  force = false,
): Promise<SaveResult> {
  for (let i = 0; i < 3; i++) {
    let cur;
    try {
      cur = await client.get(target.path);
    } catch (e) {
      return { ok: false, conflict: false, error: (e as Error).message };
    }
    if (!cur) return { ok: false, conflict: false, error: 'File not found on the server' };
    const fresh = parseOrg(cur.text, todo);
    const h = relocateHeadline(fresh, target);
    if (!h) return { ok: false, conflict: true, serverSection: null };
    const section = sectionOf(fresh.lines, h);
    const unchanged =
      section.length === target.sectionLines.length && section.every((l, k) => l === target.sectionLines[k]);
    if (!unchanged && !force) return { ok: false, conflict: true, serverSection: section.join('\n') };
    let text: string;
    try {
      text = applyHeadlineEdit(fresh, h, changes);
    } catch (e) {
      return { ok: false, conflict: false, error: (e as Error).message };
    }
    if (text === cur.text) return { ok: true, text, etag: cur.etag };
    try {
      await client.put(target.path, text, cur.etag);
      return { ok: true, text, etag: null };
    } catch (e) {
      if (e instanceof DavError && e.status === 412) {
        await sleep(200 * 2 ** i);
        continue;
      }
      return { ok: false, conflict: false, error: (e as Error).message };
    }
  }
  return { ok: false, conflict: true, serverSection: null };
}
