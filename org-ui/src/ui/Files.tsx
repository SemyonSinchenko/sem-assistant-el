// File list drawer and the rendered file view.

import { useEffect, useMemo, useState } from 'react';
import { fileColor, isReadOnly } from '../config';
import { bodyText, type Headline, type OrgFile } from '../org/parse';
import { load, save } from '../store/persist';
import { navigate } from '../store/route';
import { useStore } from '../store/store';
import { Keyword, PlanningChips, Priority, Tags } from './Chips';
import { Icon } from './Icons';
import { Inline, OrgBody } from './OrgRender';

export function FileList() {
  const { files, cache, config, route, refreshList, setDrawer, filesError } = useStore();
  const current = route.view === 'files' ? route.path ?? config.inbox.path : null;
  return (
    <nav className="drawer" aria-label="Файлы">
      <div className="dh">
        <span>Файлы</span>
        <button className="ib sm" onClick={() => void refreshList()} aria-label="Обновить список">
          <Icon name="refresh" size={16} />
        </button>
      </div>
      {files.map((f) => (
        <button
          key={f}
          className={'file' + (f === current ? ' on' : '')}
          onClick={() => {
            if (innerWidth <= 760) setDrawer(false);
            navigate({ view: 'files', path: f });
          }}
        >
          <span className="dot" style={{ ['--c' as string]: fileColor(config, f) }} />
          <span className="fname">{f}</span>
          {cache[f] && <span className="n">{cache[f].org.headlines.length}</span>}
        </button>
      ))}
      {!files.length && <div className="dnote">{filesError ? 'Ошибка: ' + filesError : 'Загрузка…'}</div>}
    </nav>
  );
}

function foldKey(path: string) {
  return 'fold:' + path;
}

export function FileView({ path }: { path: string }) {
  const { cache, loadFile, loading, errors, config, highlight } = useStore();
  const entry = cache[path];
  const [folded, setFolded] = useState<Set<number>>(() => new Set(load<number[]>(foldKey(path), [])));
  const [open, setOpen] = useState<Set<number>>(new Set());

  useEffect(() => {
    void loadFile(path, true);
    setFolded(new Set(load<number[]>(foldKey(path), [])));
    setOpen(new Set());
  }, [path, loadFile]);

  // open and reveal the headline requested via highlight (capture, "open in file")
  useEffect(() => {
    if (!entry || !highlight || highlight.path !== path) return;
    setOpen((o) => new Set(o).add(highlight.line));
    requestAnimationFrame(() => document.getElementById(`hl-${highlight.line}`)?.scrollIntoView({ block: 'center' }));
  }, [entry, highlight, path]);

  const persistFold = (s: Set<number>) => {
    setFolded(s);
    save(foldKey(path), s.size ? [...s] : null);
  };

  const org = entry?.org;
  const rows = useMemo(() => {
    if (!org) return [];
    const out: Headline[] = [];
    let hideBelow = Infinity;
    for (const h of org.headlines) {
      if (h.level > hideBelow) continue;
      hideBelow = folded.has(h.line) ? h.level : Infinity;
      out.push(h);
    }
    return out;
  }, [org, folded]);

  const ro = isReadOnly(config, path);
  const isInbox = path === config.inbox.path;

  return (
    <div className="page">
      <div className="fh">
        <div>
          <h1>{path}</h1>
          <div className="meta">
            {org ? `${org.headlines.length} заголовков` : loading[path] ? 'Загрузка…' : ''}
            {ro && ' · только чтение'}
            {errors[path] && <span className="errt"> · {errors[path]}</span>}
          </div>
        </div>
        <div className="fa">
          <button className="btn sm" onClick={() => org && persistFold(new Set(org.headlines.filter((h) => h.subtreeEnd > h.bodyEnd).map((h) => h.line)))}>
            Свернуть всё
          </button>
          <button className="btn sm" onClick={() => persistFold(new Set())}>
            Развернуть всё
          </button>
          <button className="btn sm" onClick={() => void loadFile(path, true)} aria-label="Обновить">
            <Icon name="refresh" size={15} />
          </button>
        </div>
      </div>
      {isInbox && <div className="hint">Сырые записи. Обрабатываются автоматически каждые ~30 мин.</div>}
      {org &&
        rows.map((h) => (
          <HeadlineRow
            key={h.line}
            h={h}
            org={org}
            path={path}
            readOnly={ro}
            folded={folded.has(h.line)}
            open={open.has(h.line)}
            fresh={highlight?.path === path && highlight.line === h.line}
            onFold={() => {
              const s = new Set(folded);
              if (s.has(h.line)) s.delete(h.line);
              else s.add(h.line);
              persistFold(s);
            }}
            onToggle={() => {
              const s = new Set(open);
              if (s.has(h.line)) s.delete(h.line);
              else s.add(h.line);
              setOpen(s);
            }}
          />
        ))}
      {org && !org.headlines.length && <div className="empty">Заголовков нет</div>}
    </div>
  );
}

function HeadlineRow(props: {
  h: Headline;
  org: OrgFile;
  path: string;
  readOnly: boolean;
  folded: boolean;
  open: boolean;
  fresh: boolean;
  onFold: () => void;
  onToggle: () => void;
}) {
  const { h, org, path, readOnly, folded, open, fresh } = props;
  const kids = h.subtreeEnd > h.bodyEnd;
  const body = bodyText(org, h);
  const done = !!h.keyword && org.todo.done.includes(h.keyword);
  return (
    <div className={`hl${h.level === 1 ? ' l1' : ''}${fresh ? ' new' : ''}`} id={`hl-${h.line}`} style={{ ['--lv' as string]: h.level - 1 }}>
      {kids ? (
        <button className="caret" onClick={props.onFold} aria-label={folded ? 'Развернуть ветку' : 'Свернуть ветку'}>
          {folded ? '▸' : '▾'}
        </button>
      ) : (
        <span className="caret leaf" aria-hidden="true">
          •
        </span>
      )}
      <div className="hm" onClick={props.onToggle}>
        <div className="ht">
          <Keyword kw={h.keyword} file={org} />
          <Priority p={h.priority} />
          <span className={'tt' + (done ? ' done' : '')}>{h.title ? <Inline text={h.title} /> : <i className="mut">без названия</i>}</span>
          <Tags h={h} />
          {!open && body.trim() && <span className="more">…</span>}
        </div>
        <PlanningChips h={h} file={org} />
        {open && body.trim() && <OrgBody text={body} />}
      </div>
      {!readOnly ? (
        <button className="ed" onClick={() => navigate({ view: 'edit', path, line: h.line })}>
          Править
        </button>
      ) : (
        <span />
      )}
    </div>
  );
}
