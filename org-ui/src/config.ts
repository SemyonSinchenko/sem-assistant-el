// Runtime configuration loaded from /ui/config.json (can be replaced by a volume).

import type { CaptureTemplate } from './org/capture';
import type { TodoKeywords } from './org/parse';

export interface FilterPreset {
  name: string;
  files?: string[];
  includeTags?: string[];
  excludeTags?: string[];
}

export interface Config {
  inbox: { path: string };
  templates: CaptureTemplate[];
  todoKeywords: TodoKeywords;
  readOnly: string[];
  fileColors: Record<string, string>;
  calendar: {
    defaultView: string;
    mobileDefaultView: string;
    firstDay: number;
    slotMinTime: string;
    slotMaxTime: string;
    scrollTime: string;
    bodyTimestamps: boolean;
    noDragFiles: string[];
  };
  filterPresets: FilterPreset[];
}

export const DEFAULT_CONFIG: Config = {
  inbox: { path: 'inbox-mobile.org' },
  templates: [
    { id: 'link', label: 'Ссылка', tag: 'link', title: 'firstLine', icon: 'link' },
    { id: 'task', label: 'Задача', tag: 'task', title: 'firstLine', icon: 'check' },
    { id: 'journal', label: 'Журнал', tag: 'journal', title: 'timestamp', icon: 'book' },
  ],
  todoKeywords: { active: ['TODO', 'NEXT', 'WAITING'], done: ['DONE', 'CANCELLED'] },
  readOnly: ['inbox-mobile.org'],
  fileColors: {},
  calendar: {
    defaultView: 'timeGridWeek',
    mobileDefaultView: 'timeGridDay',
    firstDay: 1,
    slotMinTime: '06:00',
    slotMaxTime: '24:00',
    scrollTime: '08:00',
    bodyTimestamps: false,
    noDragFiles: [],
  },
  filterPresets: [{ name: 'Всё' }],
};

export async function loadConfig(): Promise<Config> {
  try {
    const r = await fetch(import.meta.env.BASE_URL + 'config.json', { cache: 'no-cache' });
    if (!r.ok) return DEFAULT_CONFIG;
    const c = (await r.json()) as Partial<Config>;
    return {
      ...DEFAULT_CONFIG,
      ...c,
      inbox: { ...DEFAULT_CONFIG.inbox, ...c.inbox },
      calendar: { ...DEFAULT_CONFIG.calendar, ...c.calendar },
      templates: (c.templates ?? DEFAULT_CONFIG.templates).map((t) => ({ ...t, title: t.title ?? 'firstLine' })),
    };
  } catch {
    return DEFAULT_CONFIG;
  }
}

const PALETTE = ['#1d2bd8', '#c2410c', '#0e7490', '#a21caf', '#b45309', '#15803d', '#be123c', '#4338ca', '#64748b'];

export function fileColor(config: Config, path: string): string {
  const c = config.fileColors[path];
  if (c) return c;
  let h = 0;
  for (const ch of path) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return PALETTE[h % PALETTE.length];
}

export function isReadOnly(config: Config, path: string): boolean {
  return path === config.inbox.path || config.readOnly.includes(path);
}
