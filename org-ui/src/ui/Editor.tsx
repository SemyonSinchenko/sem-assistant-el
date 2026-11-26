// Editor of one existing headline: only its headline line, planning line and body change.

import { useEffect, useMemo, useState } from 'react';
import { isReadOnly } from '../config';
import { saveHeadline, type EditTarget } from '../dav/ops';
import { applyHeadlineEdit, diffLines, EditError, relocateHeadline, type HeadlineChanges } from '../org/edit';
import { bodyText, hasRepeater, parseOrg, type Headline, type OrgFile } from '../org/parse';
import { formatTimestamp, repeaterString, withRepeater, type Timestamp } from '../org/timestamp';
import { load, save } from '../store/persist';
import { navigate } from '../store/route';
import { useStore } from '../store/store';
import { Dialog } from './Dialog';

interface Form {
  keyword: string;
  priority: string;
  title: string;
  tags: string[];
  sDate: string;
  sStart: string;
  sEnd: string;
  sRep: string;
  dDate: string;
  dTime: string;
  body: string;
}

function formFrom(org: OrgFile, h: Headline): Form {
  const s = h.planning.scheduled;
  const d = h.planning.deadline;
  return {
    keyword: h.keyword ?? '',
    priority: h.priority ?? '',
    title: h.title,
    tags: [...h.tags],
    sDate: s?.date ?? '',
    sStart: s?.start ?? '',
    sEnd: s?.end ?? '',
    sRep: repeaterString(s),
    dDate: d?.date ?? '',
    dTime: d?.start ?? '',
    body: bodyText(org, h),
  };
}

function newTs(date: string): Timestamp {
  return { active: true, date, weekday: 'Mon', start: null, end: null, repeater: null, cookies: [], rangeEnd: null };
}

/** Build a timestamp from form fields, keeping the style of ORIG. */
function tsFrom(orig: Timestamp | null, date: string, start: string, end: string, rep: string | null): Timestamp | null {
  if (!date) return null;
  let ts: Timestamp = { ...(orig ?? newTs(date)), date, start: start || null, end: start && end ? end : null };
  if (rep !== null) ts = withRepeater(ts, rep || null);
  return ts;
}

function changesOf(org: OrgFile, h: Headline, f: Form): HeadlineChanges {
  const ch: HeadlineChanges = {};
  if ((h.keyword ?? '') !== f.keyword) ch.keyword = f.keyword || null;
  if ((h.priority ?? '') !== f.priority) ch.priority = f.priority || null;
  if (h.title !== f.title) ch.title = f.title;
  if (h.tags.join(':') !== f.tags.join(':')) ch.tags = f.tags;
  const s0 = h.planning.scheduled;
  const s1 = tsFrom(s0, f.sDate, f.sStart, f.sEnd, f.sRep);
  if ((s0 ? formatTimestamp(s0) : '') !== (s1 ? formatTimestamp(s1) : '')) ch.scheduled = s1;
  const d0 = h.planning.deadline;
  const d1 = tsFrom(d0, f.dDate, f.dTime, d0?.end ?? '', null);
  if ((d0 ? formatTimestamp(d0) : '') !== (d1 ? formatTimestamp(d1) : '')) ch.deadline = d1;
  if (bodyText(org, h) !== f.body.replace(/\s+$/, '')) ch.body = f.body;
  return ch;
}

const REPEATS = ['', '+1d', '+1w', '+2w', '+1m', '+1y'];

export function Editor({ path, line }: { path: string; line: number }) {
  const { loadFile, config, setFile, toast, client, cache, lastRoute } = useStore();
  const [base, setBase] = useState<{ org: OrgFile; h: Headline } | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [error, setError] = useState('');
  const [missing, setMissing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [conflict, setConflict] = useState<string | null | undefined>(undefined);
  const [draft, setDraft] = useState<Form | null>(null);
  const [tagInput, setTagInput] = useState('');

  const draftKey = `draft:${path}:${line}`;

  useEffect(() => {
    let alive = true;
    void loadFile(path, true).then((c) => {
      if (!alive || !c) return;
      const h = c.org.headlines.find((x) => x.line === line);
      if (!h) return setMissing(true);
      setBase({ org: c.org, h });
      const f = formFrom(c.org, h);
      setForm(f);
      const d = load<{ lineText: string; form: Form } | null>(draftKey, null);
      if (d && d.lineText === c.org.lines[h.line] && JSON.stringify(d.form) !== JSON.stringify(f)) setDraft(d.form);
    });
    return () => {
      alive = false;
    };
  }, [path, line, loadFile, draftKey]);

  const changes = useMemo(() => (base && form ? changesOf(base.org, base.h, form) : {}), [base, form]);
  const dirty = Object.keys(changes).length > 0;

  useEffect(() => {
    if (!base || !form) return;
    save(draftKey, dirty ? { lineText: base.org.lines[base.h.line], form } : null);
  }, [form, dirty, base, draftKey]);

  const preview = useMemo(() => {
    if (!base || !dirty) return { diff: [], err: '' };
    try {
      const text = applyHeadlineEdit(base.org, base.h, changes);
      const next = parseOrg(text, base.org.todo);
      const nh = relocateHeadline(next, { id: base.h.id, line: base.h.line, lineText: next.lines[base.h.line] ?? '' }) ?? next.headlines.find((x) => x.line === base.h.line);
      const oldL = base.org.lines.slice(base.h.line, base.h.bodyEnd);
      const newL = nh ? next.lines.slice(nh.line, nh.bodyEnd) : [];
      return { diff: diffLines(oldL, newL).filter((d) => d.kind !== 'same'), err: '' };
    } catch (e) {
      return { diff: [], err: e instanceof EditError ? e.message : String(e) };
    }
  }, [base, changes, dirty]);

  const allTags = useMemo(() => {
    const s = new Set<string>();
    for (const c of Object.values(cache)) for (const h of c.org.headlines) h.tags.forEach((t) => s.add(t));
    return [...s].sort();
  }, [cache]);

  const leave = () => {
    save(draftKey, null);
    const prev = lastRoute && lastRoute.view !== 'edit' && lastRoute.view !== 'new' ? lastRoute : null;
    navigate(prev ?? { view: 'files', path });
  };

  if (isReadOnly(config, path)) return <div className="page empty">Файл {path} только для чтения</div>;
  if (missing) return <div className="page empty">Заголовок не найден: файл изменился. Откройте его заново.</div>;
  if (!base || !form) return <div className="page empty">Загрузка…</div>;

  const { org, h } = base;
  const set = (patch: Partial<Form>) => setForm({ ...form, ...patch });
  const repeating = hasRepeater(h);
  const reps = [...REPEATS];
  if (form.sRep && !reps.includes(form.sRep)) reps.push(form.sRep);

  const target: EditTarget = {
    path,
    id: h.id,
    line: h.line,
    lineText: org.lines[h.line],
    sectionLines: org.lines.slice(h.line, h.bodyEnd),
  };

  const doSave = async (force = false) => {
    if (!client || busy) return;
    setError('');
    setBusy(true);
    const r = await saveHeadline(client, target, changes, org.todo, force);
    setBusy(false);
    if (r.ok) {
      setFile(path, r.text, r.etag);
      toast({ text: 'Сохранено: ' + path, detail: 'изменены только строки этого заголовка' });
      leave();
    } else if (r.conflict) setConflict(r.serverSection);
    else setError(r.error);
  };

  const addTag = (v: string) => {
    const t = v.trim().replace(/[\s:]+/g, '_');
    if (t && !form.tags.includes(t)) set({ tags: [...form.tags, t] });
    setTagInput('');
  };

  return (
    <div className="page">
      <div className="eh">
        <button className="btn" onClick={() => (dirty ? setConfirmCancel(true) : leave())}>
          ← Назад
        </button>
        <h1>Правка</h1>
      </div>
      <div className="target">
        Файл: <b>{path}</b>, меняется только этот заголовок
      </div>
      {draft && (
        <div className="hint row-b">
          Есть несохранённый черновик.
          <button className="btn sm" onClick={() => (setForm(draft), setDraft(null))}>
            Восстановить
          </button>
          <button className="btn sm" onClick={() => setDraft(null)}>
            Нет
          </button>
        </div>
      )}
      <div className="eg">
        <form
          className="form"
          onSubmit={(e) => {
            e.preventDefault();
            void doSave();
          }}
        >
          <div className="row">
            <label>
              Состояние
              <select value={form.keyword} onChange={(e) => set({ keyword: e.target.value })}>
                <option value="">—</option>
                {org.todo.active.map((k) => (
                  <option key={k} value={k}>
                    {k}
                  </option>
                ))}
                {org.todo.done.map((k) => (
                  <option key={k} value={k} disabled={repeating && k !== h.keyword}>
                    {k}
                    {repeating && k !== h.keyword ? ' (повторяющаяся — отмечать в Emacs/Orgzly)' : ''}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Приоритет
              <select value={form.priority} onChange={(e) => set({ priority: e.target.value })}>
                {['', 'A', 'B', 'C'].map((p) => (
                  <option key={p} value={p}>
                    {p || '—'}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <label>
            Заголовок
            <input className="ti" value={form.title} onChange={(e) => set({ title: e.target.value })} autoComplete="off" />
          </label>
          <div className="lab">
            Теги
            <div className="tagin">
              {form.tags.map((t, i) => (
                <span className="tg" key={t}>
                  {t}
                  <button type="button" aria-label={'Убрать тег ' + t} onClick={() => set({ tags: form.tags.filter((_, j) => j !== i) })}>
                    ×
                  </button>
                </span>
              ))}
              <input
                list="taglist"
                value={tagInput}
                placeholder="добавить и Enter"
                autoComplete="off"
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ',') {
                    e.preventDefault();
                    addTag(tagInput);
                  } else if (e.key === 'Backspace' && !tagInput && form.tags.length) set({ tags: form.tags.slice(0, -1) });
                }}
                onBlur={() => tagInput && addTag(tagInput)}
              />
              <datalist id="taglist">
                {allTags.map((t) => (
                  <option key={t} value={t} />
                ))}
              </datalist>
            </div>
          </div>
          <fieldset>
            <legend>SCHEDULED</legend>
            <div className="row">
              <label>
                Дата
                <input type="date" value={form.sDate} onChange={(e) => set({ sDate: e.target.value })} />
              </label>
              <label>
                Начало
                <input type="time" value={form.sStart} onChange={(e) => set({ sStart: e.target.value })} />
              </label>
              <label>
                Конец
                <input type="time" value={form.sEnd} onChange={(e) => set({ sEnd: e.target.value })} disabled={!form.sStart} />
              </label>
              <label>
                Повтор
                <select value={form.sRep} onChange={(e) => set({ sRep: e.target.value })}>
                  {reps.map((r) => (
                    <option key={r} value={r}>
                      {r || 'нет'}
                    </option>
                  ))}
                </select>
              </label>
            </div>
          </fieldset>
          <fieldset>
            <legend>DEADLINE</legend>
            <div className="row">
              <label>
                Дата
                <input type="date" value={form.dDate} onChange={(e) => set({ dDate: e.target.value })} />
              </label>
              <label>
                Время
                <input type="time" value={form.dTime} onChange={(e) => set({ dTime: e.target.value })} disabled={!form.dDate} />
              </label>
            </div>
          </fieldset>
          <label>
            Текст
            <textarea rows={10} value={form.body} onChange={(e) => set({ body: e.target.value })} />
          </label>
          {h.properties.length > 0 && (
            <details>
              <summary>Свойства (не редактируются)</summary>
              <pre>{h.properties.map(([k, v]) => `:${k}: ${v}`).join('\n')}</pre>
            </details>
          )}
          <div className="err">{error || preview.err}</div>
          <div className="acts">
            <button className="btn pri" type="submit" disabled={!dirty || busy || !!preview.err}>
              {busy ? 'Сохраняю…' : 'Сохранить'}
            </button>
            <button className="btn" type="button" onClick={() => (dirty ? setConfirmCancel(true) : leave())}>
              Отмена
            </button>
          </div>
        </form>
        <aside className="src">
          <div className="sh">Изменения</div>
          {preview.diff.length ? (
            <pre className="diff">
              {preview.diff.map((d, i) => (
                <div key={i} className={d.kind}>
                  {(d.kind === 'del' ? '− ' : '+ ') + d.text}
                </div>
              ))}
            </pre>
          ) : (
            <pre className="mut">Пока ничего не изменено</pre>
          )}
        </aside>
      </div>
      {confirmCancel && (
        <Dialog
          title="Отменить изменения?"
          onClose={() => setConfirmCancel(false)}
          actions={
            <>
              <button className="btn pri" onClick={leave}>
                Отменить изменения
              </button>
              <button className="btn" onClick={() => setConfirmCancel(false)}>
                Продолжить правку
              </button>
            </>
          }
        >
          Несохранённые изменения будут потеряны.
        </Dialog>
      )}
      {conflict !== undefined && (
        <Dialog
          title="Заголовок изменился на сервере"
          onClose={() => setConflict(undefined)}
          actions={
            <>
              <button className="btn pri" disabled={conflict === null} onClick={() => (setConflict(undefined), void doSave(true))}>
                Перезаписать моей версией
              </button>
              <button className="btn" onClick={() => setConflict(undefined)}>
                Отменить
              </button>
            </>
          }
        >
          {conflict === null ? (
            <p>Заголовок не найден в свежей версии файла. Откройте файл заново.</p>
          ) : (
            <div className="cmp">
              <div>
                <div className="sh">На сервере</div>
                <pre>{conflict}</pre>
              </div>
              <div>
                <div className="sh">Было, когда открыли</div>
                <pre>{target.sectionLines.join('\n')}</pre>
              </div>
            </div>
          )}
        </Dialog>
      )}
    </div>
  );
}
