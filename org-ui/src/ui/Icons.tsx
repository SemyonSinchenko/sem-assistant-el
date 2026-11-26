// Inline SVG icons.

const P = { fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

export function Icon({ name, size = 18 }: { name: string; size?: number }) {
  const s = { width: size, height: size, viewBox: '0 0 24 24', ...P, 'aria-hidden': true };
  switch (name) {
    case 'menu':
      return <svg {...s}><path d="M4 6h16M4 12h16M4 18h16" /></svg>;
    case 'plus':
      return <svg {...s} strokeWidth={2.4}><path d="M12 5v14M5 12h14" /></svg>;
    case 'link':
      return <svg {...s}><path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1" /><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1" /></svg>;
    case 'check':
      return <svg {...s}><rect x="4" y="4" width="16" height="16" rx="3" /><path d="M8 12l3 3 5-6" /></svg>;
    case 'book':
      return <svg {...s}><path d="M6 4h10a3 3 0 0 1 3 3v13H9a3 3 0 0 1-3-3z" /><path d="M10 9h5M10 13h5" /></svg>;
    case 'refresh':
      return <svg {...s}><path d="M20 11a8 8 0 1 0-2.3 5.7" /><path d="M20 4v7h-7" /></svg>;
    case 'outbox':
      return <svg {...s}><path d="M4 14v5h16v-5" /><path d="M12 3v12M7 8l5-5 5 5" /></svg>;
    case 'close':
      return <svg {...s}><path d="M6 6l12 12M18 6L6 18" /></svg>;
    default:
      return <svg {...s}><circle cx="12" cy="12" r="8" /></svg>;
  }
}
