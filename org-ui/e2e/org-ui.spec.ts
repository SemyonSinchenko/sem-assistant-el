import { expect, test, type Page } from '@playwright/test';
import { readFileSync, rmSync, writeFileSync, readdirSync } from 'node:fs';

const ROOT = process.env.ROOT ?? '/tmp/org-ui-e2e';
const TASKS = `${ROOT}/tasks`;
const USER = process.env.DAV_USER ?? 'orgzly';
const PASS = process.env.DAV_PASS ?? 'E2eTestPassword2026Strong';

const read = (f: string) => readFileSync(`${TASKS}/${f}`, 'utf8');
const write = (f: string, s: string) => writeFileSync(`${TASKS}/${f}`, s);

const TASKS_ORG = `#+TITLE: Tasks
* TODO Купить фильтры :task:
SCHEDULED: <2026-11-26 Thu 14:00-15:00>
:PROPERTIES:
:ID: 11111111-aaaa
:FILETAGS: :routine:
:END:
Тело задачи.

* TODO Повторяющаяся :task:
SCHEDULED: <2026-11-23 Mon +1w>
:PROPERTIES:
:ID: 22222222-bbbb
:END:
* TODO Без времени
SCHEDULED: <2026-11-27 Fri>
* Ссылки [[https://orgmode.org][*Org* manual]] :link:
см. *важно /очень/* и [[https://a.org][описание]], =код=
`;

const INBOX = `* старое  :task:
:PROPERTIES:
:CREATED:  [2026-11-25 Wed 10:00]
:END:
`;

test.beforeEach(async ({ page }) => {
  for (const f of readdirSync(TASKS)) rmSync(`${TASKS}/${f}`, { recursive: true, force: true });
  write('tasks.org', TASKS_ORG);
  write('inbox-mobile.org', INBOX);
  write('errors.org', '* TODO [#A] err\nDEADLINE: <2026-11-20 Fri>\n');
  writeFileSync(`${TASKS}/notes.txt`, 'not org');
  await page.clock.install({ time: new Date('2026-11-26T12:48:00+01:00') });
});

async function login(page: Page, hash = '') {
  await page.goto('./' + hash);
  await page.getByLabel('User').fill(USER);
  await page.getByLabel('Password').fill(PASS);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.locator('.drawer .file').first()).toBeVisible();
}

test('login shows a flat alphabetical list of .org files', async ({ page }) => {
  await login(page);
  await expect(page.locator('.drawer .file .fname')).toHaveText(['errors.org', 'inbox-mobile.org', 'tasks.org']);
  await page.locator('.drawer .file', { hasText: 'tasks.org' }).click();
  await expect(page.locator('.hl')).toHaveCount(4);
});

test('wrong password stays on the login screen', async ({ page }) => {
  await page.goto('./');
  await page.getByLabel('User').fill(USER);
  await page.getByLabel('Password').fill('wrong');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByText('Wrong username or password')).toBeVisible();
});

test('rich markup in titles and bodies renders', async ({ page }) => {
  await login(page, '#files/tasks.org');
  const row = page.locator('.hl', { hasText: 'Ссылки' });
  await expect(row.getByRole('link', { name: 'Org manual' })).toHaveAttribute('href', 'https://orgmode.org');
  await row.locator('.hm').click();
  await expect(row.getByRole('link', { name: 'описание' })).toBeVisible();
  await expect(row.locator('b', { hasText: 'важно' })).toBeVisible();
});

test('inbox is read-only and shows the hint', async ({ page }) => {
  await login(page, '#files/inbox-mobile.org');
  await expect(page.getByText('Raw entries')).toBeVisible();
  await expect(page.locator('.hl')).toHaveCount(1);
  await expect(page.getByRole('button', { name: 'Edit' })).toHaveCount(0);
});

test('capture a task appends exactly the expected entry', async ({ page }) => {
  await login(page);
  await page.getByRole('button', { name: 'New' }).click();
  await page.getByRole('button', { name: /Task/ }).click();
  await page.getByLabel('Text').fill('позвонить бухгалтеру завтра !\nподробности');
  await expect(page.locator('.src pre')).toContainText(':CREATED:  [2026-11-26 Thu 12:48]');
  await page.getByLabel('Text').press('Control+Enter');
  await expect(page.getByText('Added to inbox-mobile.org')).toBeVisible();
  expect(read('inbox-mobile.org')).toBe(
    INBOX + '* позвонить бухгалтеру завтра !  :task:\n:PROPERTIES:\n:CREATED:  [2026-11-26 Thu 12:48]\n:END:\nподробности\n',
  );
  await expect(page.locator('.hl.new')).toHaveCount(1);
});

test('journal capture: date+time headline, all text in the body, no CREATED', async ({ page }) => {
  await login(page, '#new/journal');
  await page.getByLabel('Text').fill('Долго гулял\nветер сильный');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('Added to')).toBeVisible();
  expect(read('inbox-mobile.org')).toBe(INBOX + '* 2026-11-26 12:48  :journal:\nДолго гулял\nветер сильный\n');
});

test('link capture into a file without trailing newline adds a separator', async ({ page }) => {
  write('inbox-mobile.org', '* x');
  await login(page, '#new/link');
  await page.getByLabel('Text').fill('https://orgmode.org/');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('Added to')).toBeVisible();
  expect(read('inbox-mobile.org')).toBe('* x\n* https://orgmode.org/  :link:\n:PROPERTIES:\n:CREATED:  [2026-11-26 Thu 12:48]\n:END:\n');
});

test('two tabs appending at the same time keep both entries', async ({ page, context }) => {
  await login(page);
  const page2 = await context.newPage();
  await page2.clock.install({ time: new Date('2026-11-26T12:49:00+01:00') });
  await page2.goto('./#new/task');
  await page.goto('./#new/task');
  await page.getByLabel('Text').fill('первая');
  await page2.getByLabel('Text').fill('вторая');
  await Promise.all([page.getByRole('button', { name: 'Add' }).click(), page2.getByRole('button', { name: 'Add' }).click()]);
  await expect(page.getByText('Added to')).toBeVisible({ timeout: 15000 });
  await expect(page2.getByText('Added to')).toBeVisible({ timeout: 15000 });
  const inbox = read('inbox-mobile.org');
  expect(inbox.startsWith(INBOX)).toBe(true);
  expect(inbox).toContain('* первая  :task:');
  expect(inbox).toContain('* вторая  :task:');
});

test('offline capture goes to the outbox and is sent later', async ({ page, context }) => {
  await login(page);
  await context.setOffline(true);
  await page.goto('./#new/task');
  await page.getByLabel('Text').fill('оффлайн задача');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('Saved locally')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Unsent entries' })).toContainText('1');
  expect(read('inbox-mobile.org')).toBe(INBOX);
  await page.getByRole('button', { name: 'Unsent entries' }).click();
  await expect(page.getByRole('button', { name: 'Send now' })).toBeVisible();
  // coming back online flushes the outbox by itself
  await context.setOffline(false);
  await expect(page.getByRole('button', { name: 'Unsent entries' })).toHaveCount(0, { timeout: 10000 });
  expect(read('inbox-mobile.org')).toBe(INBOX + '* оффлайн задача  :task:\n:PROPERTIES:\n:CREATED:  [2026-11-26 Thu 12:48]\n:END:\n');
});

test('editing a headline changes only its lines and keeps properties', async ({ page }) => {
  await login(page, '#files/tasks.org');
  await page.locator('.hl', { hasText: 'Купить фильтры' }).getByRole('button', { name: 'Edit' }).click();
  await page.getByLabel('State').selectOption('NEXT');
  await page.getByLabel('Date').first().fill('2026-11-28');
  await page.getByLabel('Text').fill('Тело задачи.\nещё строка');
  await expect(page.locator('.diff .add')).toHaveCount(3);
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByText('Saved: tasks.org')).toBeVisible();
  expect(read('tasks.org')).toBe(
    TASKS_ORG.replace('* TODO Купить фильтры', '* NEXT Купить фильтры')
      .replace('<2026-11-26 Thu 14:00-15:00>', '<2026-11-28 Sat 14:00-15:00>')
      .replace('Тело задачи.\n', 'Тело задачи.\nещё строка\n'),
  );
});

test('a headline changed on the server shows the conflict dialog', async ({ page }) => {
  await login(page, '#edit/tasks.org/1');
  await page.getByLabel('Title').fill('Купить фильтры (UI)');
  write('tasks.org', TASKS_ORG.replace('Тело задачи.', 'Изменено в Emacs.'));
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('dialog', { name: 'The headline changed on the server' })).toBeVisible();
  await expect(page.getByRole('dialog')).toContainText('Изменено в Emacs.');
  await page.getByRole('dialog').getByRole('button', { name: 'Cancel' }).click();
  expect(read('tasks.org')).toContain('Изменено в Emacs.');
  expect(read('tasks.org')).not.toContain('(UI)');
});

test('DONE is not available for repeating entries', async ({ page }) => {
  await login(page, '#edit/tasks.org/9');
  await expect(page.getByLabel('Title')).toHaveValue('Повторяющаяся');
  await expect(page.locator('option[value="DONE"]')).toBeDisabled();
  await expect(page.locator('option[value="NEXT"]')).toBeEnabled();
});

test('calendar shows events, preview and opens the file', async ({ page }) => {
  await login(page, '#calendar/timeGridWeek/2026-11-23');
  await expect(page.locator('.fc-event', { hasText: 'Купить фильтры' })).toBeVisible();
  await expect(page.locator('.fc-event', { hasText: 'Повторяющаяся' })).toHaveCount(1);
  await expect(page.locator('.fc-event', { hasText: 'Без времени' })).toBeVisible();
  await page.locator('.fc-event', { hasText: 'Купить фильтры' }).click();
  await expect(page.locator('.prev h2')).toContainText('Купить фильтры');
  await page.getByRole('button', { name: 'Open in file' }).click();
  await expect(page).toHaveURL(/#files\/tasks\.org$/);
  await expect(page.locator('.hl', { hasText: 'Тело задачи.' })).toBeVisible();
});

test('calendar filter by tag hides entries', async ({ page }) => {
  await login(page, '#calendar/timeGridWeek/2026-11-23');
  await expect(page.locator('.fc-event', { hasText: 'Без времени' })).toBeVisible();
  await page.getByRole('button', { name: /Filter/ }).click();
  await page.locator('.tagf', { hasText: 'task' }).click();
  await expect(page.locator('.fq code').first()).toHaveText('+task -DONE');
  await expect(page.locator('.fc-event', { hasText: 'Без времени' })).toHaveCount(0);
  await expect(page.locator('.fc-event', { hasText: 'Купить фильтры' })).toBeVisible();
});

test('drag-n-drop moves SCHEDULED and undo restores it', async ({ page }) => {
  await login(page, '#calendar/dayGridMonth/2026-11-01');
  const ev = page.locator('.fc-event', { hasText: 'Без времени' });
  await expect(ev).toBeVisible();
  const target = page.locator('td.fc-day[data-date="2026-11-30"]');
  const a = (await ev.boundingBox())!;
  const b = (await target.boundingBox())!;
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x + a.width / 2 + 5, a.y + a.height / 2 + 5, { steps: 3 });
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 10 });
  await page.mouse.up();
  await expect(page.getByText('SCHEDULED: <2026-11-27 Fri> → <2026-11-30 Mon>')).toBeVisible();
  expect(read('tasks.org')).toBe(TASKS_ORG.replace('<2026-11-27 Fri>', '<2026-11-30 Mon>'));
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect.poll(() => read('tasks.org'), { timeout: 10000 }).toBe(TASKS_ORG);
});
