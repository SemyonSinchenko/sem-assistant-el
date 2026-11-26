// New entry (capture): one text field, live preview, append to the inbox.

import { useEffect, useMemo, useRef, useState } from 'react';
import { buildCapture } from '../org/capture';
import { navigate } from '../store/route';
import { useStore } from '../store/store';

export function Capture({ templateId, initialText }: { templateId: string; initialText: string }) {
  const { config, capture, toast, lastRoute } = useStore();
  const tpl = config.templates.find((t) => t.id === templateId);
  const [text, setText] = useState(initialText);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(() => new Date());
  const ta = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 15000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    const el = ta.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = Math.max(160, el.scrollHeight + 2) + 'px';
  }, [text]);

  const result = useMemo(() => (tpl ? buildCapture(tpl, text, now) : { entry: null, escaped: false }), [tpl, text, now]);

  if (!tpl) return <div className="page empty">Template "{templateId}» not found in config.json</div>;

  const back = () => {
    const prev = lastRoute && lastRoute.view !== 'new' && lastRoute.view !== 'edit' ? lastRoute : null;
    navigate(prev ?? { view: 'files', path: config.inbox.path });
  };

  const submit = async () => {
    // CREATED is the moment of pressing the button, not of sending
    const r = buildCapture(tpl, text, new Date());
    if (!r.entry || busy) return;
    setBusy(true);
    const res = await capture(r.entry);
    setBusy(false);
    if (res === 'sent') toast({ text: 'Added to ' + config.inbox.path });
    else toast({ text: 'Saved locally, will send later', detail: 'outbox' });
    const prev = lastRoute && lastRoute.view !== 'new' && lastRoute.view !== 'edit' ? lastRoute : null;
    if (!prev || prev.view === 'files') navigate({ view: 'files', path: config.inbox.path });
    else navigate(prev);
  };

  return (
    <div className="page">
      <div className="eh">
        <button className="btn" onClick={back}>
          ← Back
        </button>
        <h1>New: {tpl.label}</h1>
        <span className="tg ro">:{tpl.tag}:</span>
      </div>
      <div className="target">
        Will be appended to the end of <b>{config.inbox.path}</b>
        {tpl.title === 'timestamp' && ' · headline is the date and time, all text goes to the body'}
      </div>
      <div className="eg">
        <div className="form">
          <label>
            Text
            <textarea
              ref={ta}
              autoFocus
              value={text}
              placeholder={tpl.placeholder}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
                  e.preventDefault();
                  void submit();
                }
              }}
            />
          </label>
          {result.escaped && <div className="hint">Lines starting with "* " are indented by one space so they don't become headlines.</div>}
          <div className="acts">
            <button className="btn pri" disabled={!result.entry || busy} onClick={() => void submit()}>
              {busy ? 'Sending…' : 'Add'}
            </button>
            <button className="btn" onClick={back}>
              Cancel
            </button>
            <span className="meta kbd">Ctrl/⌘+Enter</span>
          </div>
        </div>
        <aside className="src">
          <div className="sh">
            Goes to the file
            <button
              className="btn sm"
              disabled={!result.entry}
              onClick={() =>
                navigator.clipboard?.writeText(result.entry ?? '').then(
                  () => toast({ text: 'Copied' }),
                  () => toast({ text: 'Clipboard unavailable' }),
                )
              }
            >
              Copy
            </button>
          </div>
          <pre>{result.entry ?? '…'}</pre>
        </aside>
      </div>
    </div>
  );
}
