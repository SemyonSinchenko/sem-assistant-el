// Top bar: drawer toggle, view switch, capture menu, outbox indicator.

import { useEffect, useRef, useState } from 'react';
import { navigate } from '../store/route';
import { useStore } from '../store/store';
import { Icon } from './Icons';

export function Header() {
  const { route, drawer, setDrawer, config, outbox, online, logout } = useStore();
  const [menu, setMenu] = useState(false);
  const [box, setBox] = useState(false);
  const wrap = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const close = (e: MouseEvent) => {
      if (wrap.current && !wrap.current.contains(e.target as Node)) {
        setMenu(false);
        setBox(false);
      }
    };
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && (setMenu(false), setBox(false));
    document.addEventListener('click', close);
    document.addEventListener('keydown', esc);
    return () => {
      document.removeEventListener('click', close);
      document.removeEventListener('keydown', esc);
    };
  }, []);

  const where =
    route.view === 'files'
      ? route.path ?? config.inbox.path
      : route.view === 'calendar'
        ? 'Calendar'
        : route.view === 'new'
          ? '→ ' + config.inbox.path
          : 'Edit: ' + route.path;
  const seg = route.view === 'calendar' ? 'calendar' : 'files';

  return (
    <header className="top" ref={wrap}>
      <button className="ib" onClick={() => setDrawer(!drawer)} aria-label="Show or hide files">
        <Icon name="menu" size={20} />
      </button>
      <div className="brand">
        org<span>·</span>ui
      </div>
      <div className="where">
        {!online && <span className="off">offline · </span>}
        {where}
      </div>
      <div className="seg" role="tablist">
        <button className={seg === 'files' ? 'on' : ''} onClick={() => navigate({ view: 'files', path: useStore.getState().lastFile() })}>
          Files
        </button>
        <button className={seg === 'calendar' ? 'on' : ''} onClick={() => navigate({ view: 'calendar', cal: null, date: null })}>
          Calendar
        </button>
      </div>
      {outbox.length > 0 && (
        <div className="newwrap">
          <button className="btn warn" onClick={() => (setBox(!box), setMenu(false))} aria-label="Unsent entries">
            <Icon name="outbox" size={16} />
            {outbox.length}
          </button>
          {box && <OutboxMenu />}
        </div>
      )}
      <div className="newwrap">
        <button className="btn pri" aria-haspopup="true" aria-expanded={menu} onClick={() => (setMenu(!menu), setBox(false))}>
          <Icon name="plus" size={16} />
          <span className="nl">New</span>
        </button>
        {menu && (
          <div className="menu">
            {config.templates.map((t) => (
              <button
                key={t.id}
                onClick={() => {
                  setMenu(false);
                  navigate({ view: 'new', template: t.id, text: '' });
                }}
              >
                <span className="ico">
                  <Icon name={t.icon ?? 'plus'} />
                </span>
                <span>
                  <b>{t.label}</b>
                  <small>tag :{t.tag}:</small>
                </span>
              </button>
            ))}
            <div className="foot">Always appended to the end of {config.inbox.path}</div>
            <button className="logout" onClick={() => (setMenu(false), logout())}>
              Sign out
            </button>
          </div>
        )}
      </div>
    </header>
  );
}

function OutboxMenu() {
  const { outbox, flushOutbox, flushing } = useStore();
  return (
    <div className="menu wide">
      <div className="mh">Unsent: {outbox.length}</div>
      {outbox.map((o) => (
        <div key={o.id} className="obi">
          <code>{o.entry.split('\n')[0]}</code>
          <small>
            {new Date(o.createdAt).toLocaleString()} {o.error ? '· ' + o.error : ''}
          </small>
        </div>
      ))}
      <button className="btn pri sm" disabled={flushing} onClick={() => void flushOutbox()}>
        {flushing ? 'Sending…' : 'Send now'}
      </button>
    </div>
  );
}
