// Calendar view (FullCalendar): day/week/month, filter, preview panel, drag-n-drop of SCHEDULED.

import FullCalendar from '@fullcalendar/react';
import dayGridPlugin from '@fullcalendar/daygrid';
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import ruLocale from '@fullcalendar/core/locales/ru';
import type { DatesSetArg, EventClickArg, EventContentArg, EventDropArg } from '@fullcalendar/core';
import type { EventResizeDoneArg } from '@fullcalendar/interaction';
import { useEffect, useMemo, useRef, useState } from 'react';
import { fileColor, isReadOnly, type FilterPreset } from '../config';
import { saveHeadline } from '../dav/ops';
import { ancestors, bodyText, sectionSource, type Headline } from '../org/parse';
import { formatTimestamp, fromMinutes, hhmm, minutes, ymd, type Timestamp } from '../org/timestamp';
import { load, save } from '../store/persist';
import { navigate, type CalView } from '../store/route';
import { useStore } from '../store/store';
import { allTagsOf, buildEvents, defaultFilter, filterCount, filterQuery, NO_KEYWORD, type CalEvent, type Filter } from './calendarModel';
import { Keyword, PlanningChips, Priority, Tags } from './Chips';
import { Icon } from './Icons';
import { Inline, OrgBody, plainTitle } from './OrgRender';

interface Sel {
  path: string;
  line: number;
}

export function CalendarView({ view, date }: { view: CalView | null; date: string | null }) {
  const { config, files, cache, loadAll, client, setFile, toast } = useStore();
  const [filter, setFilterState] = useState<Filter>(() => ({ ...defaultFilter(config), ...load<Partial<Filter>>('filter', {}) }));
  const [fopen, setFopen] = useState(false);
  const [range, setRange] = useState<{ from: string; to: string } | null>(null);
  const [sel, setSel] = useState<Sel | null>(null);
  const [userPresets, setUserPresets] = useState<FilterPreset[]>(() => load<FilterPreset[]>('presets', []));
  const cal = useRef<FullCalendar>(null);
  const mobile = innerWidth <= 760;

  useEffect(() => {
    void loadAll();
  }, [loadAll, files]);

  const setFilter = (f: Filter) => {
    setFilterState(f);
    save('filter', f);
  };

  const loaded = useMemo(
    () =>
      files
        .filter((p) => cache[p])
        .map((p) => ({
          path: p,
          org: cache[p].org,
          color: fileColor(config, p),
          readOnly: isReadOnly(config, p),
          noDrag: config.calendar.noDragFiles.includes(p),
        })),
    [files, cache, config],
  );

  const events = useMemo(() => {
    if (!range) return [];
    return buildEvents(loaded, filter, range.from, range.to, (h) => plainTitle(h.title) || '(без названия)').map((e) => ({
      id: e.id,
      title: e.title,
      start: e.start,
      end: e.end,
      allDay: e.allDay,
      display: e.display,
      editable: e.draggable,
      durationEditable: e.draggable && !e.allDay,
      backgroundColor: e.kind === 'deadline' ? 'transparent' : e.display ? e.color + '22' : e.color,
      borderColor: e.kind === 'deadline' ? '#c81e1e' : e.color,
      textColor: e.kind === 'deadline' ? 'var(--ink)' : '#fff',
      classNames: [`ev-${e.kind}`, e.done ? 'ev-done' : '', e.repeating ? 'ev-rep' : '', sel && sel.path === e.path && sel.line === e.line ? 'ev-sel' : ''],
      extendedProps: e,
    }));
  }, [loaded, filter, range, sel]);

  const tags = useMemo(() => allTagsOf(loaded.map((l) => l.org)), [loaded]);
  const keywords = useMemo(() => {
    const s = new Set<string>(config.todoKeywords.active);
    loaded.forEach((l) => l.org.todo.active.forEach((k) => s.add(k)));
    return [...s, NO_KEYWORD];
  }, [loaded, config]);

  const onDates = (arg: DatesSetArg) => {
    const from = ymd(arg.start);
    const endIncl = new Date(arg.end);
    endIncl.setDate(endIncl.getDate() - 1);
    setRange((r) => (r && r.from === from && r.to === ymd(endIncl) ? r : { from, to: ymd(endIncl) }));
    const hash = `#calendar/${arg.view.type}/${ymd(arg.view.currentStart)}`;
    // only while the calendar is the current route: a re-render during navigation
    // away must not overwrite the new hash
    if (location.hash !== hash && (location.hash === '' || location.hash.startsWith('#calendar')))
      history.replaceState(null, '', hash);
  };

  /** Rewrite SCHEDULED of the entry behind EV; returns false on failure. */
  const reschedule = async (path: string, line: number, make: (old: Timestamp) => Timestamp | null, undoable: boolean): Promise<boolean> => {
    // read the store directly: undo runs after the cache was updated by the first save
    const c = useStore.getState().cache[path] ?? (await useStore.getState().loadFile(path));
    if (!client || !c) return false;
    const h = c.org.headlines.find((x) => x.line === line);
    const old = h?.planning.scheduled;
    if (!h || !old) return false;
    const next = make(old);
    if (!next) return false;
    const target = { path, id: h.id, line: h.line, lineText: c.org.lines[h.line], sectionLines: c.org.lines.slice(h.line, h.bodyEnd) };
    const r = await saveHeadline(client, target, { scheduled: next }, c.org.todo);
    if (!r.ok) {
      toast({ text: r.conflict ? 'Запись изменилась на сервере — обновите календарь' : 'Не сохранено: ' + r.error });
      if (r.conflict) void useStore.getState().loadFile(path, true);
      return false;
    }
    setFile(path, r.text, r.etag);
    toast({
      text: `SCHEDULED: ${formatTimestamp(old)} → ${formatTimestamp(next)}`,
      ttl: 6000,
      action: undoable ? { label: 'Отменить', run: () => void reschedule(path, line, () => old, false) } : undefined,
    });
    return true;
  };

  const onDrop = async (info: EventDropArg | EventResizeDoneArg) => {
    const e = info.event.extendedProps as CalEvent;
    const start = info.event.start;
    if (!start) return info.revert();
    const allDay = info.event.allDay;
    const evEnd = info.event.end;
    const ok = await reschedule(
      e.path,
      e.line,
      (old) => {
        const date = ymd(start);
        if (allDay) return { ...old, date, start: null, end: null };
        const st = hhmm(start);
        let end: string | null = null;
        if ('endDelta' in info && evEnd) end = hhmm(evEnd);
        else if (old.start && old.end) {
          // keep the duration; drop the end when it would cross midnight
          const em = minutes(st) + minutes(old.end) - minutes(old.start);
          end = em < 24 * 60 ? fromMinutes(em) : null;
        }
        if (evEnd && ymd(evEnd) !== date && !(evEnd.getHours() === 0 && evEnd.getMinutes() === 0)) end = null;
        if (end === '00:00') end = null;
        return { ...old, date, start: st, end };
      },
      true,
    );
    if (!ok) info.revert();
  };

  const presets = [...config.filterPresets, ...userPresets];
  const applyPreset = (p: FilterPreset) =>
    setFilter({ ...defaultFilter(config), files: p.files ?? null, include: p.includeTags ?? [], exclude: p.excludeTags ?? [] });

  const selected = sel && cache[sel.path] ? cache[sel.path].org.headlines.find((h) => h.line === sel.line) ?? null : null;

  return (
    <div className="calwrap">
      <div className="cal">
        <div className="ctb">
          <button className="btn" aria-expanded={fopen} onClick={() => setFopen(!fopen)}>
            Фильтр {filterCount(filter, defaultFilter(config)) > 0 && <span className="badge">{filterCount(filter, defaultFilter(config))}</span>}
          </button>
          <button className="btn sm" onClick={() => void loadAll(true)} aria-label="Обновить">
            <Icon name="refresh" size={15} />
          </button>
          <span className="fq">
            Запрос: <code>{filterQuery(filter)}</code>
          </span>
        </div>
        {fopen && (
          <FilterPanel
            filter={filter}
            setFilter={setFilter}
            files={files}
            tags={tags}
            keywords={keywords}
            presets={presets}
            applyPreset={applyPreset}
            savePreset={(name) => {
              const p: FilterPreset = { name, files: filter.files ?? undefined, includeTags: filter.include, excludeTags: filter.exclude };
              const next = [...userPresets.filter((x) => x.name !== name), p];
              setUserPresets(next);
              save('presets', next);
            }}
          />
        )}
        <div className="fcwrap">
          <FullCalendar
            ref={cal}
            plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
            initialView={view ?? (mobile ? config.calendar.mobileDefaultView : config.calendar.defaultView)}
            initialDate={date ?? undefined}
            headerToolbar={{ left: 'today prev,next', center: 'title', right: 'timeGridDay,timeGridWeek,dayGridMonth' }}
            buttonText={{ today: 'Сегодня', day: 'День', week: 'Неделя', month: 'Месяц' }}
            locales={[ruLocale]}
            locale="ru"
            firstDay={config.calendar.firstDay}
            slotMinTime={config.calendar.slotMinTime}
            slotMaxTime={config.calendar.slotMaxTime}
            scrollTime={config.calendar.scrollTime}
            nowIndicator
            navLinks
            dayMaxEvents
            moreLinkClick="day"
            allDayText="весь день"
            slotLabelFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
            eventTimeFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
            height="100%"
            longPressDelay={400}
            events={events}
            datesSet={onDates}
            eventClick={(a: EventClickArg) => {
              const e = a.event.extendedProps as CalEvent;
              setSel({ path: e.path, line: e.line });
            }}
            eventDrop={(i) => void onDrop(i)}
            eventResize={(i) => void onDrop(i)}
            eventContent={(arg: EventContentArg) => {
              const e = arg.event.extendedProps as CalEvent;
              if (e.kind === 'warning') return null;
              return (
                <div className="fc-ev" title={e.draggable ? undefined : e.kind === 'deadline' ? 'DEADLINE — двигается только в редакторе' : e.repeating ? 'Повторяющаяся — двигается только в редакторе' : undefined}>
                  {e.kind === 'deadline' && <i className="dl">DL</i>}
                  {arg.timeText && <span className="tm">{arg.timeText}</span>}
                  {e.repeating && '↻ '}
                  <span className="et">{arg.event.title}</span>
                </div>
              );
            }}
          />
        </div>
      </div>
      {selected && sel && <Preview sel={sel} h={selected} onClose={() => setSel(null)} />}
    </div>
  );
}

function FilterPanel(props: {
  filter: Filter;
  setFilter: (f: Filter) => void;
  files: string[];
  tags: string[];
  keywords: string[];
  presets: FilterPreset[];
  applyPreset: (p: FilterPreset) => void;
  savePreset: (name: string) => void;
}) {
  const { filter: F, setFilter, files, tags, keywords } = props;
  const { config } = useStore();
  const [pname, setPname] = useState('');
  const fileSet = F.files ?? files;
  const toggleFile = (f: string) => {
    const next = fileSet.includes(f) ? fileSet.filter((x) => x !== f) : [...fileSet, f];
    setFilter({ ...F, files: next.length === files.length ? null : next });
  };
  const cycleTag = (t: string) => {
    if (F.include.includes(t)) setFilter({ ...F, include: F.include.filter((x) => x !== t), exclude: [...F.exclude, t] });
    else if (F.exclude.includes(t)) setFilter({ ...F, exclude: F.exclude.filter((x) => x !== t) });
    else setFilter({ ...F, include: [...F.include, t] });
  };
  const stateSet = F.states ?? keywords;
  const toggleState = (k: string) => {
    const next = stateSet.includes(k) ? stateSet.filter((x) => x !== k) : [...stateSet, k];
    setFilter({ ...F, states: next.length === keywords.length ? null : next });
  };
  const opt = (key: 'showDone' | 'showDeadline' | 'showBody' | 'showUntimed', label: string) => (
    <label className="chk">
      <input type="checkbox" checked={F[key]} onChange={(e) => setFilter({ ...F, [key]: e.target.checked })} />
      {label}
    </label>
  );
  return (
    <div className="fp">
      <div className="fg">
        <div className="fl">Пресеты</div>
        <div className="chips">
          {props.presets.map((p) => (
            <button key={p.name} className="chip" onClick={() => props.applyPreset(p)}>
              {p.name}
            </button>
          ))}
          <span className="psave">
            <input value={pname} onChange={(e) => setPname(e.target.value)} placeholder="имя пресета" />
            <button className="chip" disabled={!pname.trim()} onClick={() => (props.savePreset(pname.trim()), setPname(''))}>
              Сохранить как пресет
            </button>
          </span>
        </div>
      </div>
      <div className="fg">
        <div className="fl">Файлы</div>
        <div className="chips">
          <button className="chip" onClick={() => setFilter({ ...F, files: null })}>
            все
          </button>
          <button className="chip" onClick={() => setFilter({ ...F, files: [] })}>
            ни одного
          </button>
          {files.map((f) => (
            <label className="chk" key={f}>
              <input type="checkbox" checked={fileSet.includes(f)} onChange={() => toggleFile(f)} />
              <span className="dot" style={{ ['--c' as string]: fileColor(config, f) }} />
              {f}
            </label>
          ))}
        </div>
      </div>
      <div className="fg">
        <div className="fl">Теги</div>
        <div className="chips">
          {tags.map((t) => {
            const s = F.include.includes(t) ? 'inc' : F.exclude.includes(t) ? 'exc' : '';
            return (
              <button key={t} className={'tagf ' + s} onClick={() => cycleTag(t)} title="клик: только с тегом → скрыть → выкл">
                {s === 'inc' ? '+' : s === 'exc' ? '−' : ''}
                {t}
              </button>
            );
          })}
          {!tags.length && <span className="mut">нет тегов</span>}
        </div>
      </div>
      <div className="fg">
        <div className="fl">Состояния</div>
        <div className="chips">
          {keywords.map((k) => (
            <label className="chk" key={k}>
              <input type="checkbox" checked={stateSet.includes(k)} onChange={() => toggleState(k)} />
              {k}
            </label>
          ))}
        </div>
      </div>
      <div className="fg">
        <div className="fl">Показать</div>
        <div className="chips">
          {opt('showDone', 'DONE')}
          {opt('showDeadline', 'DEADLINE')}
          {opt('showBody', 'таймстемпы из тела')}
          {opt('showUntimed', 'записи без времени')}
        </div>
      </div>
      <div className="fq">
        Запрос: <code>{filterQuery(F)}</code>
        <button className="chip sm" onClick={() => navigator.clipboard?.writeText(filterQuery(F))}>
          копировать
        </button>
        · фильтр запоминается в этом браузере
      </div>
    </div>
  );
}

function Preview({ sel, h, onClose }: { sel: Sel; h: Headline; onClose: () => void }) {
  const { cache, config } = useStore();
  const org = cache[sel.path].org;
  const crumbs = ancestors(org, h);
  const ro = isReadOnly(config, sel.path);
  const body = bodyText(org, h);
  const done = !!h.keyword && org.todo.done.includes(h.keyword);
  useEffect(() => {
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    document.addEventListener('keydown', esc);
    return () => document.removeEventListener('keydown', esc);
  }, [onClose]);
  return (
    <aside className="prev">
      <div className="ph">
        <span className="dot" style={{ ['--c' as string]: fileColor(config, sel.path) }} />
        {sel.path} <span className="ro">только чтение</span>
        <button className="ib" onClick={onClose} aria-label="Закрыть">
          <Icon name="close" size={16} />
        </button>
      </div>
      {crumbs.length > 0 && <div className="crumb">{crumbs.map((c) => plainTitle(c.title)).join(' › ')}</div>}
      <h2>
        <Keyword kw={h.keyword} file={org} />
        <Priority p={h.priority} />
        <span className={done ? 'done' : ''}>
          <Inline text={h.title} />
        </span>
      </h2>
      <div className="ht">
        <Tags h={h} />
      </div>
      <PlanningChips h={h} file={org} />
      {body.trim() ? <OrgBody text={body} /> : <p className="more">Без текста</p>}
      <div className="pa">
        {!ro && (
          <button className="btn pri" onClick={() => navigate({ view: 'edit', path: sel.path, line: h.line })}>
            Править
          </button>
        )}
        <button
          className="btn"
          onClick={() => {
            useStore.setState({ highlight: { path: sel.path, line: h.line } });
            navigate({ view: 'files', path: sel.path });
          }}
        >
          Открыть в файле
        </button>
      </div>
      <details>
        <summary>Org-исходник</summary>
        <pre>{sectionSource(org, h)}</pre>
      </details>
    </aside>
  );
}
