// Login screen, same fields as organice's WebDAV sign-in.

import { useState, type FormEvent } from 'react';
import { useStore } from '../store/store';

export function Login() {
  const login = useStore((s) => s.login);
  const [url, setUrl] = useState(() => location.origin + '/');
  const [user, setUser] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    const ok = await login({ url: url.trim(), user, password });
    setBusy(false);
    if (!ok) setError('Wrong username or password');
  };

  return (
    <div className="login">
      <form className="form card" onSubmit={submit}>
        <div className="brand big">
          org<span>·</span>ui
        </div>
        <label>
          WebDAV URL
          <input value={url} onChange={(e) => setUrl(e.target.value)} inputMode="url" autoComplete="url" required />
        </label>
        <label>
          User
          <input value={user} onChange={(e) => setUser(e.target.value)} autoComplete="username" required autoFocus />
        </label>
        <label>
          Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
        </label>
        <div className="err">{error}</div>
        <button className="btn pri" type="submit" disabled={busy}>
          {busy ? 'Checking…' : 'Sign in'}
        </button>
        <p className="meta">Credentials are stored in this browser (localStorage), like organice does.</p>
      </form>
    </div>
  );
}
