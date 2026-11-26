// Rendering of Org inline markup and body blocks as React elements (no innerHTML).

import { Fragment, useState, type ReactNode } from 'react';

const SAFE_URL = /^(https?:|mailto:)/i;

const INLINE_RE =
  /\[\[([^\]\n]+?)\](?:\[([^\]\n]+?)\])?\]|(https?:\/\/[^\s<>\]]+[^\s<>\].,;:!?)'"])|(^|[\s(])([*/=~+])(\S(?:[^\n]*?\S)?)\5(?=[\s).,;:!?'"]|$)/g;

function link(url: string, label: ReactNode, key: number): ReactNode {
  if (!SAFE_URL.test(url)) return <span key={key} className="olink-x">{label}</span>;
  return (
    <a key={key} href={url} target="_blank" rel="noopener noreferrer" onClick={(e) => e.stopPropagation()}>
      {label}
    </a>
  );
}

/** Render inline Org markup: links, bare URLs, *bold* /italic/ =code= ~code~ +strike+. */
export function Inline({ text }: { text: string }) {
  return <>{renderInline(text)}</>;
}

export function renderInline(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  let k = 0;
  INLINE_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = INLINE_RE.exec(text))) {
    let start = m.index;
    if (m[4] !== undefined) start += m[4].length;
    if (start > last) out.push(text.slice(last, start));
    if (m[1]) out.push(link(m[1], m[2] ? renderInline(m[2]) : m[1], k++));
    else if (m[3]) out.push(link(m[3], m[3], k++));
    else {
      const inner = m[6];
      switch (m[5]) {
        case '*':
          out.push(<b key={k++}>{renderInline(inner)}</b>);
          break;
        case '/':
          out.push(<i key={k++}>{renderInline(inner)}</i>);
          break;
        case '+':
          out.push(<s key={k++}>{renderInline(inner)}</s>);
          break;
        default:
          out.push(<code key={k++}>{inner}</code>);
      }
    }
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

/** Plain text of a title (link descriptions instead of [[url][desc]]). */
export function plainTitle(text: string): string {
  return text.replace(/\[\[([^\]]+?)\](?:\[([^\]]+?)\])?\]/g, (_, u, d) => d || u);
}

type Block =
  | { kind: 'p'; lines: string[] }
  | { kind: 'list'; items: { indent: number; checkbox: string | null; text: string; ordered: boolean }[] }
  | { kind: 'block'; name: string; lines: string[] }
  | { kind: 'drawer'; name: string; lines: string[] }
  | { kind: 'table'; lines: string[] }
  | { kind: 'blank' };

const LIST_RE = /^([ \t]*)([-+]|\d+[.)]|[ \t]+\*)[ \t]+(?:\[([ Xx-])\][ \t]+)?(.*)$/;

function parseBlocks(lines: string[]): Block[] {
  const out: Block[] = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    const b = l.match(/^[ \t]*#\+begin_(\S+)/i);
    if (b) {
      const name = b[1].toLowerCase();
      const body: string[] = [];
      let j = i + 1;
      while (j < lines.length && !new RegExp(`^[ \\t]*#\\+end_${name}\\b`, 'i').test(lines[j])) body.push(lines[j++]);
      out.push({ kind: 'block', name, lines: body });
      i = j;
      continue;
    }
    const d = l.match(/^[ \t]*:([A-Za-z0-9_-]+):[ \t]*$/);
    if (d && d[1].toUpperCase() !== 'END') {
      let j = i + 1;
      const body: string[] = [];
      while (j < lines.length && !/^[ \t]*:END:[ \t]*$/i.test(lines[j])) body.push(lines[j++]);
      if (j < lines.length) {
        out.push({ kind: 'drawer', name: d[1], lines: body });
        i = j;
        continue;
      }
    }
    if (/^[ \t]*\|/.test(l)) {
      const t: string[] = [];
      while (i < lines.length && /^[ \t]*\|/.test(lines[i])) t.push(lines[i++]);
      i--;
      out.push({ kind: 'table', lines: t });
      continue;
    }
    const li = l.match(LIST_RE);
    if (li) {
      const prev = out[out.length - 1];
      const item = { indent: li[1].length, checkbox: li[3] ?? null, text: li[4], ordered: /\d/.test(li[2]) };
      if (prev?.kind === 'list') prev.items.push(item);
      else out.push({ kind: 'list', items: [item] });
      continue;
    }
    if (!l.trim()) {
      out.push({ kind: 'blank' });
      continue;
    }
    const prev = out[out.length - 1];
    if (prev?.kind === 'list' && /^[ \t]+\S/.test(l)) {
      prev.items[prev.items.length - 1].text += ' ' + l.trim();
      continue;
    }
    if (/^[ \t]*#\+/.test(l)) continue; // keywords like #+TITLE are not shown in bodies
    if (prev?.kind === 'p') prev.lines.push(l);
    else out.push({ kind: 'p', lines: [l] });
  }
  return out;
}

function Sensitive({ lines }: { lines: string[] }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="sens">
      <button type="button" className="sens-h" onClick={(e) => (e.stopPropagation(), setOpen(!open))} aria-expanded={open}>
        🔒 sensitive {open ? '▾' : '▸'}
      </button>
      {open && <pre>{lines.join('\n')}</pre>}
    </div>
  );
}

/** Render an Org body (lines between drawers and the next headline). */
export function OrgBody({ text }: { text: string }) {
  const blocks = parseBlocks(text.split('\n'));
  return (
    <div className="bd">
      {blocks.map((b, i) => {
        switch (b.kind) {
          case 'blank':
            return null;
          case 'p':
            return (
              <p key={i}>
                {b.lines.map((l, j) => (
                  <Fragment key={j}>
                    {j > 0 && <br />}
                    {renderInline(l)}
                  </Fragment>
                ))}
              </p>
            );
          case 'list': {
            const ordered = b.items[0].ordered;
            const items = b.items.map((it, j) => (
              <li key={j} style={{ marginLeft: Math.max(0, it.indent - b.items[0].indent) * 8 }}>
                {it.checkbox !== null && (
                  <span className={'cb' + (it.checkbox === ' ' ? '' : it.checkbox === '-' ? ' part' : ' on')} aria-hidden="true">
                    {it.checkbox === ' ' ? '' : it.checkbox === '-' ? '–' : '✓'}
                  </span>
                )}
                {renderInline(it.text)}
              </li>
            ));
            return ordered ? <ol key={i}>{items}</ol> : <ul key={i}>{items}</ul>;
          }
          case 'block':
            if (b.name === 'sensitive') return <Sensitive key={i} lines={b.lines} />;
            if (b.name === 'quote') return <blockquote key={i}>{b.lines.map((l, j) => <p key={j}>{renderInline(l)}</p>)}</blockquote>;
            return <pre key={i}>{b.lines.join('\n')}</pre>;
          case 'drawer':
            return (
              <details key={i} className="drawer-d" onClick={(e) => e.stopPropagation()}>
                <summary>:{b.name}:</summary>
                <pre>{b.lines.join('\n')}</pre>
              </details>
            );
          case 'table':
            return <pre key={i} className="table">{b.lines.join('\n')}</pre>;
        }
      })}
    </div>
  );
}
