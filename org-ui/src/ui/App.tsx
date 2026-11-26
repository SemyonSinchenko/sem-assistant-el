// Root component: auth gate, layout, routing, background outbox flushing.

import { useEffect } from 'react';
import { loadConfig } from '../config';
import { parseHash } from '../store/route';
import { useStore } from '../store/store';
import { CalendarView } from './Calendar';
import { Capture } from './Capture';
import { Editor } from './Editor';
import { FileList, FileView } from './Files';
import { Header } from './Header';
import { Login } from './Login';

export function App() {
  const { authState, route, drawer, setDrawer, config } = useStore();

  useEffect(() => {
    void loadConfig().then((c) => {
      useStore.getState().setConfig(c);
      void useStore.getState().checkAuth();
    });
    const onHash = () => useStore.getState().setRoute(parseHash(location.hash));
    const flush = () => void useStore.getState().flushOutbox();
    const online = () => (useStore.setState({ online: true }), flush());
    const offline = () => useStore.setState({ online: false });
    window.addEventListener('hashchange', onHash);
    window.addEventListener('online', online);
    window.addEventListener('offline', offline);
    const timer = setInterval(flush, 30000);
    return () => {
      window.removeEventListener('hashchange', onHash);
      window.removeEventListener('online', online);
      window.removeEventListener('offline', offline);
      clearInterval(timer);
    };
  }, []);

  useEffect(() => {
    if (authState === 'in') void useStore.getState().flushOutbox();
  }, [authState]);

  useEffect(() => {
    const esc = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && innerWidth <= 760 && useStore.getState().drawer) setDrawer(false);
    };
    document.addEventListener('keydown', esc);
    return () => document.removeEventListener('keydown', esc);
  }, [setDrawer]);

  if (authState === 'out') return <Login />;

  let main;
  switch (route.view) {
    case 'files':
      main = <FileView path={route.path ?? useStore.getState().lastFile() ?? config.inbox.path} />;
      break;
    case 'calendar':
      main = <CalendarView view={route.cal} date={route.date} />;
      break;
    case 'new':
      main = <Capture key={route.template} templateId={route.template} initialText={route.text} />;
      break;
    case 'edit':
      main = <Editor key={`${route.path}:${route.line}`} path={route.path} line={route.line} />;
      break;
  }

  return (
    <div className={drawer ? '' : 'nodrawer'}>
      <Header />
      <div className="app">
        <FileList />
        <main className={route.view === 'calendar' ? 'calmain' : ''}>{main}</main>
        {drawer && <div className="scrim" onClick={() => setDrawer(false)} />}
      </div>
      <Toasts />
    </div>
  );
}

function Toasts() {
  const { toasts, dismissToast } = useStore();
  return (
    <div className="toasts" role="status" aria-live="polite">
      {toasts.map((t) => (
        <div className="toast" key={t.id}>
          <div>
            {t.text}
            {t.detail && <small>{t.detail}</small>}
          </div>
          {t.action && (
            <button
              className="btn sm"
              onClick={() => {
                t.action!.run();
                dismissToast(t.id);
              }}
            >
              {t.action.label}
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
