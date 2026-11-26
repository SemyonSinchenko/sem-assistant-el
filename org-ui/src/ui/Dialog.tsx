// Built-in modal dialog (instead of window.confirm).

import { useEffect, type ReactNode } from 'react';

export function Dialog(props: { title: string; children: ReactNode; actions: ReactNode; onClose: () => void }) {
  useEffect(() => {
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && props.onClose();
    document.addEventListener('keydown', esc);
    return () => document.removeEventListener('keydown', esc);
  }, [props]);
  return (
    <div className="modal-bg" onClick={props.onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={props.title} onClick={(e) => e.stopPropagation()}>
        <h2>{props.title}</h2>
        <div className="modal-b">{props.children}</div>
        <div className="acts">{props.actions}</div>
      </div>
    </div>
  );
}
