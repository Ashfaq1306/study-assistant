// Study Mate admin panel. Plain ES modules, no build step: served by the API at /admin/.
// Every piece of user data goes into the page through textContent (see el()), never as HTML.

const API = '/v1';
const STORE = 'sa-admin-session';

// ---------- tiny DOM helpers ----------

/** el('div', { class: 'x', onclick }, 'text', child, [more]) */
function el(tag, attrs = {}, ...children) {
  const node = document.createElementNS(attrs.svg ? 'http://www.w3.org/2000/svg' : 'http://www.w3.org/1999/xhtml', tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === 'svg' || value === undefined || value === null || value === false) continue;
    if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2), value);
    else if (key === 'value' && 'value' in node) node.value = value;
    else if (key === 'checked') node.checked = Boolean(value);
    else node.setAttribute(key, value === true ? '' : String(value));
  }
  const add = (child) => {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) child.forEach(add);
    else node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  };
  children.forEach(add);
  return node;
}

/** Replaces a node's children, skipping null, undefined and false (replaceChildren would print them). */
function fill(node, ...children) {
  node.replaceChildren(...children.flat(Infinity).filter((c) => c !== null && c !== undefined && c !== false));
}

const root = document.getElementById('root');
const mount = (node) => fill(root, node);

const fmt = {
  num: (n) => (n === null || n === undefined ? '—' : Number(n).toLocaleString()),
  date: (iso) => (iso ? new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : '—'),
  dateTime: (iso) =>
    iso
      ? new Date(iso).toLocaleString(undefined, { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
      : '—',
  ago(iso) {
    if (!iso) return 'never';
    const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
    if (mins < 2) return 'just now';
    if (mins < 60) return `${mins} min ago`;
    const hours = Math.round(mins / 60);
    if (hours < 48) return `${hours} h ago`;
    return `${Math.round(hours / 24)} days ago`;
  },
  age(iso) {
    const dob = new Date(iso);
    const now = new Date();
    let age = now.getFullYear() - dob.getFullYear();
    if (now < new Date(now.getFullYear(), dob.getMonth(), dob.getDate())) age--;
    return age;
  },
  /** 135 -> "2 h 15 min" */
  minutes(m) {
    if (!m) return '0 min';
    const h = Math.floor(m / 60);
    const r = m % 60;
    return h === 0 ? `${r} min` : r === 0 ? `${h} h` : `${h} h ${r} min`;
  },
  device(ua) {
    if (!ua) return 'Unknown device';
    if (/admin panel/i.test(ua)) return 'Admin panel';
    if (/dart|okhttp|android/i.test(ua)) return 'Phone app';
    if (/windows/i.test(ua)) return 'Windows browser';
    if (/mac os/i.test(ua)) return 'Mac browser';
    if (/iphone|ipad/i.test(ua)) return 'iPhone browser';
    return ua.length > 40 ? `${ua.slice(0, 40)}…` : ua;
  },
};

// ---------- session + API ----------

let session = loadSession();

function loadSession() {
  try {
    return JSON.parse(sessionStorage.getItem(STORE) ?? 'null');
  } catch {
    return null;
  }
}

function saveSession(value) {
  session = value;
  try {
    if (value) sessionStorage.setItem(STORE, JSON.stringify(value));
    else sessionStorage.removeItem(STORE);
  } catch {
    // Private mode: the session lasts until the tab closes.
  }
}

class ApiError extends Error {
  constructor(status, body) {
    super(body?.error?.message ?? `Request failed (${status}).`);
    this.status = status;
    this.code = body?.error?.code;
    this.fields = body?.error?.details?.fields;
  }
}

let refreshing = null;

async function refreshTokens() {
  const res = await fetch(`${API}/auth/refresh`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ refreshToken: session?.refreshToken }),
  });
  if (!res.ok) return false;
  const { tokens } = await res.json();
  saveSession({ ...session, ...tokens });
  return true;
}

async function api(path, { method = 'GET', body, retried = false } = {}) {
  const headers = {};
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (session?.accessToken) headers.authorization = `Bearer ${session.accessToken}`;
  let res;
  try {
    res = await fetch(`${API}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError(0, { error: { message: 'Cannot reach the server. Check the connection and try again.' } });
  }
  if (res.status === 401 && session?.refreshToken && !retried) {
    const ok = await (refreshing ??= refreshTokens().finally(() => (refreshing = null)));
    if (ok) return api(path, { method, body, retried: true });
    signOut('Your session ended. Please sign in again.');
    throw new ApiError(401, null);
  }
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  if (!res.ok) throw new ApiError(res.status, data);
  return data;
}

/** Ends a session on the server; best effort. */
function revoke(refreshToken) {
  if (!refreshToken) return;
  fetch(`${API}/auth/logout`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  }).catch(() => {});
}

function signOut(message) {
  setLive(null);
  const refreshToken = session?.refreshToken;
  saveSession(null);
  if (!message) revoke(refreshToken);
  // Opened from the app: tell it, so it can close the panel.
  window.StudyAssistantApp?.postMessage?.('signedOut');
  renderLogin(message);
}

// ---------- small UI pieces ----------

const brand = (text) => el('div', { class: 'brand' }, el('span', { class: 'brand-mark', 'aria-hidden': 'true' }, '◆'), text);

function pageHead(title, subtitle, ...right) {
  return el('div', { class: 'page-head' }, el('div', {}, el('h1', {}, title), subtitle ? el('p', { class: 'sub' }, subtitle) : null), right);
}

const loading = () => el('div', { class: 'loading', role: 'status' }, 'Loading…');
const errorBanner = (message) => el('div', { class: 'banner err', role: 'alert' }, message);

/**
 * Loads a page. A silent load (the live refresh) keeps what is on screen until the new data
 * is in, and on failure only marks the live badge as offline.
 */
async function load(main, title, fn, silent = false) {
  if (!silent) fill(main, pageHead(title), loading());
  try {
    await fn();
    liveState.ok = true;
    liveState.at = new Date();
  } catch (e) {
    if (e.status === 401) return;
    liveState.ok = false;
    if (silent) return drawLiveBadges();
    fill(main, pageHead(title), errorBanner(e.message), el('button', { class: 'btn ghost', onclick: () => route() }, 'Try again'));
  }
  drawLiveBadges();
}

// ---------- live refresh ----------

/** Every page (and an open account) refreshes itself this often while the tab is visible. */
const LIVE_MS = 10_000;
const liveState = { timer: null, fn: null, ok: true, at: null };

/** Runs [fn] every LIVE_MS while the page is visible and no account or dialog is open over it. */
function setLive(fn) {
  clearInterval(liveState.timer);
  liveState.fn = fn;
  liveState.timer = fn
    ? setInterval(() => {
        if (!document.hidden && !document.querySelector('.scrim')) fn();
      }, LIVE_MS)
    : null;
}

/** "● Live · updated 10:42:31", redrawn in place after every refresh. */
function liveBadge() {
  return el('span', { class: 'live-badge', 'data-live': '' });
}

function drawLiveBadges() {
  for (const badge of document.querySelectorAll('[data-live]')) {
    const time = liveState.at ? liveState.at.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '';
    badge.className = `live-badge ${liveState.ok ? 'on' : 'off'}`;
    fill(badge, el('i', { class: 'dot', 'aria-hidden': 'true' }), liveState.ok ? `Live · ${time}` : 'Reconnecting…');
  }
}

document.addEventListener('visibilitychange', () => {
  // Coming back to the tab: refresh at once instead of waiting for the next tick.
  if (!document.hidden && liveState.fn && !document.querySelector('.scrim')) liveState.fn();
});

const ROLE_PILL = { STUDENT: 'violet', PARENT: 'mint', ADMIN: 'amber' };
const rolePill = (role) => el('span', { class: `pill ${ROLE_PILL[role]}` }, role.toLowerCase());

function statusPill(u) {
  if (u.disabled) return el('span', { class: 'pill coral' }, 'Disabled');
  if (!u.verified) return el('span', { class: 'pill amber' }, 'Unverified');
  return el('span', { class: 'pill mint' }, 'Active');
}

const PRESENCE = { online: ['Online', 'mint'], signedIn: ['Signed in', 'violet'], signedOut: ['Signed out', 'grey'] };
function presencePill(p) {
  const [label, tone] = PRESENCE[p] ?? PRESENCE.signedOut;
  return el('span', { class: `pill ${tone}` }, el('i', { class: `dot ${tone}`, 'aria-hidden': 'true' }), label);
}

const EVENT_LABEL = {
  SIGNUP: ['Signed up', 'violet'],
  LOGIN: ['Signed in', 'mint'],
  LOGOUT: ['Signed out', 'grey'],
  PASSWORD_RESET: ['Reset password', 'amber'],
  ADMIN_DISABLED: ['Disabled by admin', 'coral'],
  ADMIN_ENABLED: ['Enabled by admin', 'mint'],
  ADMIN_SIGNED_OUT: ['Signed out by admin', 'amber'],
  ADMIN_PASSWORD_RESET: ['Password reset by admin', 'amber'],
  ADMIN_UNLOCKED: ['Phone unlocked by admin', 'coral'],
  ADMIN_SETTINGS: ['Changed settings', 'violet'],
};
function eventPill(kind) {
  const [label, tone] = EVENT_LABEL[kind] ?? [kind, 'grey'];
  return el('span', { class: `pill ${tone}` }, label);
}

/** An in-page confirmation (window.confirm would block the page). Resolves true or false. */
function confirmDialog({ title, message, confirm, danger = false, withReason = false }) {
  return new Promise((resolve) => {
    const reason = withReason ? el('input', { class: 'input', placeholder: 'Reason (optional), e.g. "Emailed support"', maxlength: 200 }) : null;
    const done = (ok) => {
      scrim.remove();
      document.removeEventListener('keydown', onKey);
      resolve(ok ? { ok: true, reason: reason?.value.trim() || undefined } : false);
    };
    const onKey = (e) => e.key === 'Escape' && done(false);
    const scrim = el(
      'div',
      { class: 'scrim center', onclick: (e) => e.target === scrim && done(false) },
      el(
        'div',
        { class: 'card dialog', role: 'alertdialog', 'aria-modal': 'true', 'aria-label': title },
        el('h2', {}, title),
        el('p', { class: 'sub' }, message),
        reason,
        el(
          'div',
          { class: 'actions' },
          el('button', { class: 'btn ghost', onclick: () => done(false) }, 'Cancel'),
          el('button', { class: danger ? 'btn danger' : 'btn', onclick: () => done(true) }, confirm),
        ),
      ),
    );
    document.addEventListener('keydown', onKey);
    document.body.append(scrim);
    (reason ?? scrim.querySelector('.btn.ghost')).focus();
  });
}

function toast(message, tone = 'ok') {
  const node = el('div', { class: `toast ${tone}`, role: 'status' }, message);
  document.body.append(node);
  setTimeout(() => node.remove(), 4000);
}

// ---------- login ----------

function renderLogin(message) {
  const error = el('div', { class: 'banner err', role: 'alert', hidden: !message }, message ?? '');
  const identifier = el('input', { class: 'input', name: 'identifier', autocomplete: 'username', required: true, placeholder: 'Admin ID (email)' });
  const password = el('input', { class: 'input', name: 'password', type: 'password', autocomplete: 'current-password', required: true, placeholder: 'Password' });
  const submit = el('button', { class: 'btn', type: 'submit' }, 'Sign in');

  const form = el(
    'form',
    {
      class: 'card',
      async onsubmit(event) {
        event.preventDefault();
        submit.disabled = true;
        error.hidden = true;
        try {
          const res = await fetch(`${API}/auth/login`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ identifier: identifier.value, password: password.value }),
          });
          const data = await res.json().catch(() => null);
          if (!res.ok) throw new ApiError(res.status, data);
          if (data.user.role !== 'ADMIN') {
            revoke(data.tokens.refreshToken);
            throw new ApiError(403, { error: { message: 'This account is not an admin.' } });
          }
          saveSession({ ...data.tokens, name: data.user.name, email: data.user.email });
          route();
        } catch (e) {
          error.textContent = e.message;
          error.hidden = false;
          submit.disabled = false;
        }
      },
    },
    brand('Control Room'),
    el('p', { class: 'sub', style: 'text-align:center;margin-top:-6px' }, 'Study Mate administration'),
    error,
    identifier,
    password,
    submit,
  );
  mount(el('div', { class: 'login' }, form));
  identifier.focus();
}

// ---------- shell ----------

const PAGES = {
  overview: { label: 'Overview', icon: '▦', render: renderOverview },
  users: { label: 'Accounts', icon: '◉', render: renderUsers },
  study: { label: 'Study time', icon: '◷', render: renderStudy },
  activity: { label: 'Activity log', icon: '≡', render: renderActivity },
  reports: { label: 'Reports', icon: '⚑', render: renderReports },
  settings: { label: 'Settings', icon: '⚙', render: renderSettings },
};

function currentPage() {
  const name = location.hash.replace(/^#\/?/, '').split('?')[0];
  return PAGES[name] ? name : 'overview';
}

async function route() {
  if (!session?.accessToken) return renderLogin();
  if (!session.name) {
    // Opened from the app with tokens only: fetch who is signed in.
    try {
      const me = await api('/me');
      if (me.role !== 'ADMIN') return signOut('This account is not an admin.');
      saveSession({ ...session, name: me.name, email: me.email });
    } catch {
      return;
    }
  }
  setLive(null);
  const page = currentPage();
  const main = el('main', { id: 'main' });
  mount(
    el(
      'div',
      { class: 'shell' },
      el(
        'nav',
        { class: 'side', 'aria-label': 'Sections' },
        brand(el('span', { class: 'hide-sm' }, 'Control Room')),
        Object.entries(PAGES).map(([key, p]) =>
          el(
            'button',
            { class: 'nav-btn', 'aria-current': key === page ? 'page' : undefined, onclick: () => (location.hash = `#/${key}`) },
            el('span', { class: 'nav-icon', 'aria-hidden': 'true' }, p.icon),
            el('span', {}, p.label),
          ),
        ),
        el('button', { class: 'nav-btn', onclick: () => signOut() }, el('span', { class: 'nav-icon', 'aria-hidden': 'true' }, '⏻'), el('span', {}, 'Sign out')),
        el('div', { class: 'side-foot' }, 'Signed in as', el('strong', {}, session.name ?? 'Admin'), session.email ?? ''),
      ),
      main,
    ),
  );
  PAGES[page].render(main);
}

window.addEventListener('hashchange', route);

// ---------- overview ----------

function tile(label, value, hint, tone) {
  return el(
    'div',
    { class: `card tile${tone ? ` tone-${tone}` : ''}` },
    el('div', { class: 'label' }, label),
    el('div', { class: 'value' }, value),
    el('div', { class: 'hint' }, hint ?? ''),
  );
}

function activityChart(days) {
  const w = 640;
  const h = 220;
  const pad = { l: 40, r: 8, t: 10, b: 26 };
  const max = Math.max(1, ...days.map((d) => d.studyMinutes));
  const step = Math.ceil(max / 4 / 10) * 10 || 1;
  const top = step * 4;
  const slot = (w - pad.l - pad.r) / days.length;
  const bw = Math.max(4, slot * 0.55);
  const y = (v) => pad.t + (h - pad.t - pad.b) * (1 - v / top);

  const svg = el('svg', { svg: true, class: 'chart', viewBox: `0 0 ${w} ${h}`, role: 'img', 'aria-label': 'Minutes studied per day, last 14 days' });
  for (let i = 0; i <= 4; i++) {
    const v = step * i;
    svg.append(el('line', { svg: true, class: 'grid', x1: pad.l, x2: w - pad.r, y1: y(v), y2: y(v) }));
    svg.append(el('text', { svg: true, class: 'axis', x: pad.l - 6, y: y(v) + 4, 'text-anchor': 'end' }, v >= 60 ? `${Math.round(v / 60)}h` : `${v}m`));
  }
  days.forEach((d, i) => {
    const x = pad.l + slot * i + slot / 2;
    svg.append(
      el(
        'rect',
        { svg: true, class: 'bar-a', x: x - bw / 2, y: y(d.studyMinutes), width: bw, height: Math.max(0, y(0) - y(d.studyMinutes)), rx: 4 },
        el('title', { svg: true }, `${d.date}: ${fmt.minutes(d.studyMinutes)} in ${d.sessions} sessions, ${d.exams} exams (${d.passed} passed), ${d.signups} sign-ups`),
      ),
    );
    if (i % 2 === days.length % 2) {
      const label = new Date(`${d.date}T00:00:00Z`).toLocaleDateString(undefined, { day: 'numeric', month: 'short', timeZone: 'UTC' });
      svg.append(el('text', { svg: true, class: 'axis', x, y: h - 6, 'text-anchor': 'middle' }, label));
    }
  });
  return svg;
}

const plural = (n, word) => `${fmt.num(n)} ${word}${n === 1 ? '' : 's'}`;

function liveNow(live) {
  return el(
    'section',
    { class: 'card live-card' },
    el('h2', {}, el('i', { class: 'dot mint pulse', 'aria-hidden': 'true' }), ' Live now: studying'),
    live.studying.length === 0
      ? el('p', { class: 'empty' }, 'Nobody is studying right now.')
      : el(
          'ul',
          { class: 'list' },
          live.studying.map((s) =>
            el(
              'li',
              { class: 'clickable', tabindex: 0, onclick: () => openUser(s.student.id), onkeydown: (e) => e.key === 'Enter' && openUser(s.student.id) },
              el('span', { class: 'grow' }, el('strong', {}, s.student.name), ' ', el('span', { class: 'meta' }, `${s.subject} · ${s.topics}`)),
              el(
                'span',
                { class: 'progress-cell' },
                el('span', { class: 'bar-track' }, el('span', { class: 'bar-fill', style: `width:${Math.min(100, (s.studiedMinutes / Math.max(1, s.plannedMinutes)) * 100)}%` })),
                el('span', { class: 'meta' }, `${fmt.minutes(s.studiedMinutes)} / ${fmt.minutes(s.plannedMinutes)}`),
                s.status === 'EXAM_PENDING' ? el('span', { class: 'pill amber' }, 'exam due') : el('span', { class: 'pill violet' }, 'studying'),
              ),
            ),
          ),
        ),
  );
}

function recentActivity(events) {
  return el(
    'section',
    { class: 'card' },
    el('h2', {}, 'Latest activity'),
    events.length === 0
      ? el('p', { class: 'empty' }, 'Nothing yet. Sign-ins and sign-outs appear here as they happen.')
      : el(
          'ul',
          { class: 'list' },
          events.map((e) =>
            el(
              'li',
              { class: 'clickable', tabindex: 0, onclick: () => openUser(e.user.id), onkeydown: (ev) => ev.key === 'Enter' && openUser(e.user.id) },
              el('span', {}, el('strong', {}, e.user.name), ' ', eventPill(e.kind)),
              el('span', { class: 'meta' }, fmt.ago(e.createdAt)),
            ),
          ),
        ),
    el('div', { class: 'actions' }, el('button', { class: 'btn ghost small', onclick: () => (location.hash = '#/activity') }, 'Full activity log →')),
  );
}

// ---------- AI health ----------

const AI_STATES = {
  OK: ['ok', 'AI is working', (a) => `Answering with ${a.model ?? 'Gemini'}.`],
  UNCHECKED: ['ok', 'AI not checked yet', () => 'The server checks the AI a few seconds after it starts.'],
  KEY_REJECTED: [
    'err',
    'AI key rejected',
    () =>
      'Google (or Anthropic) refused the key: it was deleted, expired or blocked. Exams fall back to practice questions and the AI helper is off. ' +
      'Fix: create a new key at aistudio.google.com/apikey, then in Render open study-assistant-api → Environment → GEMINI_API_KEY, paste it and save. Then press Check now.',
  ],
  BUSY: ['err', 'AI is busy (rate limit)', () => 'The free quota is used up for now. It recovers by itself; a paid key avoids this.'],
  NO_MODEL: ['err', 'AI model retired', () => 'None of the configured models exist any more. Update GEMINI_MODEL in Render.'],
  UNREACHABLE: ['err', "Can't reach the AI", () => 'The server could not connect to the AI service. It usually recovers by itself.'],
  ERROR: ['err', 'AI error', () => 'The AI answered with an error. Press Check now; if it stays, look at the Render logs.'],
  NOT_CONFIGURED: ['err', 'No AI set up', () => 'Exams use built-in practice questions. Add GEMINI_API_KEY in Render to turn the AI on.'],
};

function aiCard(ai, onCheck) {
  const [tone, title, text] = AI_STATES[ai.state] ?? AI_STATES.ERROR;
  const when = ai.checkedAt ? `Checked ${fmt.ago(ai.checkedAt)}` : 'Not checked yet';
  const button = el('button', { class: 'btn small', type: 'button' }, 'Check now');
  button.addEventListener('click', async () => {
    button.disabled = true;
    button.textContent = 'Checking…';
    try {
      await api('/admin/ai/check', { method: 'POST' });
    } catch (err) {
      toast(err.message, 'err');
    }
    onCheck();
  });
  return el(
    'div',
    { class: `banner ${tone} ai-status`, role: tone === 'err' ? 'alert' : 'status' },
    el('div', {}, el('strong', {}, title), el('span', { class: 'muted' }, ` · ${when}`), el('div', { class: 'ai-text' }, text(ai))),
    button,
  );
}

function renderOverview(main, silent = false) {
  if (!silent) setLive(() => renderOverview(main, true));
  load(main, 'Overview', async () => {
    const [s, ai] = await Promise.all([api('/admin/stats'), api('/admin/ai')]);
    fill(
      main,
      pageHead('Overview', 'Everything updates by itself every 10 seconds', liveBadge()),
      aiCard(ai, () => renderOverview(main, true)),
      el(
        'div',
        { class: 'tiles' },
        tile('Online now', fmt.num(s.users.online), `${plural(s.users.signedIn, 'account')} signed in`, 'mint'),
        tile('Studying now', fmt.num(s.live.studying.length), `${fmt.minutes(s.sessions.minutesToday)} studied today`, 'violet'),
        tile('Phones online', fmt.num(s.live.phonesOnline), `${plural(s.live.lockedPhones, 'phone')} locked now`, 'amber'),
        tile('Accounts', fmt.num(s.users.total), `${plural(s.users.students, 'student')} · ${plural(s.users.parents, 'parent')}`),
      ),
      el('div', { class: 'grid-2' }, liveNow(s.live), recentActivity(s.live.recent)),
      el(
        'div',
        { class: 'grid-2', style: 'margin-top:14px' },
        el('section', { class: 'card' }, el('h2', {}, 'Minutes studied, last 14 days'), activityChart(s.activity)),
        el(
          'section',
          { class: 'card' },
          el('h2', {}, 'At a glance'),
          el(
            'dl',
            { class: 'kv' },
            el('dt', {}, 'Exam pass rate'), el('dd', {}, s.exams.passRate === null ? '—' : `${s.exams.passRate}% (${fmt.num(s.exams.passed)}/${fmt.num(s.exams.submitted)})`),
            el('dt', {}, 'New accounts this week'), el('dd', {}, fmt.num(s.users.newThisWeek)),
            el('dt', {}, 'Parent links'), el('dd', {}, fmt.num(s.users.familyLinks)),
            el('dt', {}, 'Disabled accounts'), el('dd', {}, fmt.num(s.users.disabled)),
            el('dt', {}, 'Study sessions (all time)'), el('dd', {}, fmt.num(s.sessions.total)),
            el('dt', {}, 'Sessions this week'), el('dd', {}, fmt.num(s.sessions.thisWeek)),
            el('dt', {}, 'Exams this week'), el('dd', {}, fmt.num(s.exams.thisWeek)),
            el('dt', {}, 'Phones registered'), el('dd', {}, fmt.num(s.devices.registered)),
            el('dt', {}, 'App lock switched on'), el('dd', {}, fmt.num(s.devices.protectionOn)),
            el('dt', {}, 'Phones seen today'), el('dd', {}, fmt.num(s.devices.seenToday)),
            el('dt', {}, 'AI requests (24 h)'), el('dd', {}, fmt.num(s.ai.requestsToday)),
          ),
        ),
      ),
    );
  }, silent);
}

// ---------- accounts ----------

const usersState = { q: '', role: '', status: '', presence: '', page: 1 };

function select(label, options, value, onChange) {
  const node = el('select', { class: 'input', 'aria-label': label }, options.map(([v, l]) => el('option', { value: v, selected: v === value }, l)));
  node.addEventListener('change', () => onChange(node.value));
  return node;
}

function renderUsers(main) {
  const search = el('input', { class: 'input grow', type: 'search', placeholder: 'Search name, email or phone', value: usersState.q, 'aria-label': 'Search' });
  const results = el('div', {});
  const set = (key) => (value) => {
    usersState[key] = value;
    usersState.page = 1;
    refresh();
  };

  let timer;
  search.addEventListener('input', () => {
    clearTimeout(timer);
    timer = setTimeout(() => set('q')(search.value), 250);
  });

  fill(
    main,
    pageHead('Accounts', 'Every student, parent and admin. Open one to control it.', liveBadge()),
    el(
      'section',
      { class: 'card' },
      el(
        'div',
        { class: 'toolbar' },
        search,
        select('Role', [['', 'All roles'], ['STUDENT', 'Students'], ['PARENT', 'Parents'], ['ADMIN', 'Admins']], usersState.role, set('role')),
        select('Presence', [['', 'Anyone'], ['online', 'Online now'], ['signedIn', 'Signed in'], ['signedOut', 'Signed out']], usersState.presence, set('presence')),
        select('Status', [['', 'Any status'], ['active', 'Active'], ['disabled', 'Disabled'], ['unverified', 'Unverified']], usersState.status, set('status')),
      ),
      results,
    ),
  );

  async function refresh(silent = false) {
    if (!silent) fill(results, loading());
    const params = new URLSearchParams({ page: String(usersState.page), pageSize: '25' });
    for (const key of ['q', 'role', 'status', 'presence']) if (usersState[key].trim()) params.set(key, usersState[key].trim());
    try {
      const data = await api(`/admin/users?${params}`);
      const pages = Math.max(1, Math.ceil(data.total / data.pageSize));
      fill(
        results,
        data.users.length === 0
          ? el('p', { class: 'empty' }, 'No accounts match.')
          : el(
              'div',
              { class: 'table-wrap' },
              el(
                'table',
                {},
                el(
                  'thead',
                  {},
                  el(
                    'tr',
                    {},
                    el('th', {}, 'Name'),
                    el('th', {}, 'Role'),
                    el('th', {}, 'Presence'),
                    el('th', {}, 'Last seen'),
                    el('th', {}, 'Phone'),
                    el('th', { class: 'num' }, 'Studied'),
                    el('th', { class: 'num' }, 'Exams'),
                    el('th', {}, 'Status'),
                  ),
                ),
                el(
                  'tbody',
                  {},
                  data.users.map((u) =>
                    el(
                      'tr',
                      { tabindex: 0, onclick: () => openUser(u.id, refresh), onkeydown: (e) => e.key === 'Enter' && openUser(u.id, refresh) },
                      el('td', { class: 'who' }, el('strong', {}, u.name), el('span', {}, u.email ?? u.phone ?? '')),
                      el('td', {}, rolePill(u.role)),
                      el('td', {}, presencePill(u.presence)),
                      el('td', { class: 'muted' }, fmt.ago(u.lastActiveAt)),
                      el('td', {}, phoneCell(u)),
                      el('td', { class: 'num' }, u.role === 'STUDENT' ? fmt.minutes(u.studyMinutes) : '—'),
                      el('td', { class: 'num' }, u.role === 'STUDENT' ? fmt.num(u.counts.exams) : '—'),
                      el('td', {}, statusPill(u)),
                    ),
                  ),
                ),
              ),
            ),
        el(
          'div',
          { class: 'pager' },
          el('span', {}, `${fmt.num(data.total)} account${data.total === 1 ? '' : 's'} · page ${data.page} of ${pages}`),
          el(
            'span',
            { class: 'toolbar', style: 'margin:0' },
            el('button', { class: 'btn ghost small', disabled: data.page <= 1, onclick: () => ((usersState.page -= 1), refresh()) }, '← Previous'),
            el('button', { class: 'btn ghost small', disabled: data.page >= pages, onclick: () => ((usersState.page += 1), refresh()) }, 'Next →'),
          ),
        ),
      );
    } catch (e) {
      liveState.ok = e.status === 401;
      drawLiveBadges();
      if (e.status !== 401 && !silent) fill(results, errorBanner(e.message));
      return;
    }
    liveState.ok = true;
    liveState.at = new Date();
    drawLiveBadges();
  }

  setLive(() => refresh(true));
  refresh();
}

/** A student's phone: online if it synced in the last 3 minutes (it syncs about every minute). */
function phoneCell(u) {
  if (u.role !== 'STUDENT') return el('span', { class: 'muted' }, '—');
  if (!u.phoneSeenAt) return el('span', { class: 'muted' }, 'no phone');
  const online = Date.now() - new Date(u.phoneSeenAt).getTime() < 3 * 60_000;
  return online
    ? el('span', { class: 'pill mint' }, el('i', { class: 'dot mint', 'aria-hidden': 'true' }), 'online')
    : el('span', { class: 'muted' }, fmt.ago(u.phoneSeenAt));
}

function section(title, items, render, empty = 'Nothing yet.') {
  return el('section', { class: 'card' }, el('h2', {}, title), items.length === 0 ? el('p', { class: 'empty' }, empty) : el('ul', { class: 'list' }, items.map(render)));
}

function subjectBars(subjects) {
  const max = Math.max(1, ...subjects.map((s) => s.minutes));
  return el(
    'div',
    { class: 'bars' },
    subjects.map((s) =>
      el(
        'div',
        { class: 'bar-row' },
        el('span', { class: 'bar-label' }, s.subject),
        el('span', { class: 'bar-track' }, el('span', { class: 'bar-fill', style: `width:${Math.max(2, (s.minutes / max) * 100)}%` })),
        el('span', { class: 'bar-value' }, fmt.minutes(s.minutes)),
      ),
    ),
  );
}

function openUser(id, onChange) {
  const body = el('div', { class: 'drawer', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'Account details' }, loading());
  const scrim = el('div', { class: 'scrim', onclick: (e) => e.target === scrim && close() }, body);
  const close = () => {
    clearInterval(liveTimer);
    scrim.remove();
    document.removeEventListener('keydown', onKey);
    // Back to the page underneath: show what changed meanwhile.
    liveState.fn?.();
  };
  const onKey = (e) => e.key === 'Escape' && !document.querySelector('.dialog') && close();
  document.addEventListener('keydown', onKey);
  document.body.append(scrim);

  const message = el('div', { role: 'status' });

  /** Runs an account action after confirmation, then redraws. */
  const action = (label, options, run) =>
    el(
      'button',
      {
        class: options.danger ? 'btn danger small' : 'btn ghost small',
        async onclick(e) {
          const answer = await confirmDialog({ ...options, confirm: label });
          if (!answer) return;
          e.target.disabled = true;
          try {
            const result = await run(answer);
            onChange?.();
            await show(result);
          } catch (err) {
            fill(message, errorBanner(err.message));
            e.target.disabled = false;
          }
        },
      },
      label,
    );

  async function show(after) {
    try {
      const u = after?.user ?? (after?.id ? after : await api(`/admin/users/${encodeURIComponent(id)}`));
      const isStudent = u.role === 'STUDENT';
      const path = `/admin/users/${encodeURIComponent(id)}`;

      const actions =
        u.role === 'ADMIN'
          ? el('p', { class: 'sub' }, 'Admin accounts are managed on the server (npm run admin).')
          : el(
              'div',
              { class: 'action-grid' },
              isStudent && u.lock.locked
                ? action(
                    'Unlock phone',
                    {
                      title: `Unlock ${u.name}'s phone?`,
                      message: 'Every lock ends now without an exam: the study session and any parent locks. The phone follows within about a minute. The student and their parents are told.',
                      danger: true,
                      withReason: true,
                    },
                    async ({ reason }) => {
                      const r = await api(`${path}/unlock`, { method: 'POST', body: { reason } });
                      toast(`Unlocked: ${r.endedSessions + r.endedParentLocks} lock(s) ended.`);
                      return r;
                    },
                  )
                : null,
              action(
                'Sign out everywhere',
                { title: `Sign ${u.name} out everywhere?`, message: 'Every phone and browser must sign in again. App locks stay on.' },
                async () => {
                  const r = await api(`${path}/sign-out`, { method: 'POST' });
                  toast('Signed out everywhere.');
                  return r;
                },
              ),
              action(
                'Reset password',
                { title: `Give ${u.name} a new password?`, message: 'A new password is made and shown to you once. The old one stops working and every session ends.' },
                async () => {
                  const { password } = await api(`${path}/reset-password`, { method: 'POST' });
                  fill(
                    message,
                    el(
                      'div',
                      { class: 'banner ok' },
                      'New password (shown once): ',
                      el('code', { class: 'secret' }, password),
                      ' ',
                      el('button', { class: 'btn ghost small', onclick: () => navigator.clipboard?.writeText(password).then(() => toast('Copied.')) }, 'Copy'),
                    ),
                  );
                  return null;
                },
              ),
              action(
                u.disabled ? 'Enable account' : 'Disable account',
                u.disabled
                  ? { title: `Enable ${u.name}?`, message: 'They can sign in again.' }
                  : { title: `Disable ${u.name}?`, message: 'They are signed out everywhere and cannot sign in until you enable the account. Running app locks stay on.', danger: true },
                () => api(path, { method: 'PATCH', body: { disabled: !u.disabled } }),
              ),
            );

      fill(
        body,
        el(
          'div',
          { class: 'drawer-head' },
          el(
            'div',
            {},
            el('h1', {}, u.name),
            el('p', { class: 'sub' }, [u.email, u.phone].filter(Boolean).join(' · ')),
            el('div', { class: 'pills' }, rolePill(u.role), presencePill(u.presence), statusPill(u)),
          ),
          el('button', { class: 'btn ghost small', onclick: close, 'aria-label': 'Close' }, '✕'),
        ),
        message,
        el(
          'section',
          { class: `card${isStudent && u.lock.locked ? ' locked' : ''}` },
          el('h2', {}, 'Control'),
          isStudent
            ? el(
                'p',
                { class: 'lock-line' },
                u.lock.locked
                  ? [
                      el('strong', {}, '🔒 Phone is locked'),
                      u.lock.session ? ` · studying ${u.lock.session.subject} (${u.lock.session.status === 'EXAM_PENDING' ? 'waiting for the exam' : 'timer running'})` : '',
                      u.lock.parentLocks.length ? ` · ${u.lock.parentLocks.length} parent lock(s)` : '',
                    ]
                  : el('span', { class: 'muted' }, '🔓 Phone is not locked'),
              )
            : null,
          actions,
        ),
        el(
          'section',
          { class: 'card' },
          el(
            'dl',
            { class: 'kv' },
            el('dt', {}, 'Last seen'), el('dd', {}, u.lastActiveAt ? `${fmt.ago(u.lastActiveAt)} (${fmt.dateTime(u.lastActiveAt)})` : 'never'),
            u.role === 'ADMIN' ? null : [el('dt', {}, 'Age'), el('dd', {}, fmt.age(u.dateOfBirth))],
            el('dt', {}, 'Codes sent by'), el('dd', {}, u.otpChannel === 'SMS' ? 'SMS' : 'Email'),
            el('dt', {}, 'Joined'), el('dd', {}, fmt.dateTime(u.createdAt)),
          ),
        ),
        isStudent
          ? el(
              'section',
              { class: 'card' },
              el('h2', {}, 'Study time'),
              el(
                'div',
                { class: 'mini-tiles' },
                el('div', {}, el('span', {}, 'Today'), el('strong', {}, fmt.minutes(u.study.todayMinutes))),
                el('div', {}, el('span', {}, '7 days'), el('strong', {}, fmt.minutes(u.study.weekMinutes))),
                el('div', {}, el('span', {}, 'All time'), el('strong', {}, fmt.minutes(u.study.totalMinutes))),
                el('div', {}, el('span', {}, 'Sessions'), el('strong', {}, fmt.num(u.study.sessions))),
              ),
              u.study.bySubject.length ? subjectBars(u.study.bySubject) : el('p', { class: 'empty' }, 'No study yet.'),
            )
          : null,
        section('Signed in on', u.signedInDevices, (d) => el('li', {}, el('span', {}, fmt.device(d.userAgent)), el('span', { class: 'meta' }, `since ${fmt.dateTime(d.signedInAt)}`)), 'Signed out everywhere.'),
        section(
          'Sign-in history',
          u.activity,
          (a) =>
            el(
              'li',
              {},
              el('span', {}, eventPill(a.kind), ' ', el('span', { class: 'meta' }, [a.actor ? `by ${a.actor}` : fmt.device(a.userAgent), a.detail].filter(Boolean).join(' · '))),
              el('span', { class: 'meta' }, fmt.dateTime(a.createdAt)),
            ),
          'No sign-ins recorded yet.',
        ),
        isStudent ? section('Parents', u.parents, (p) => el('li', {}, el('span', {}, p.name), el('span', { class: 'meta' }, p.email ?? p.phone ?? ''))) : null,
        u.role === 'PARENT' ? section('Children', u.children, (c) => el('li', {}, el('span', {}, c.name), el('span', { class: 'meta' }, c.email ?? c.phone ?? ''))) : null,
        isStudent
          ? section('Phones', u.devices, (d) =>
              el(
                'li',
                {},
                el('span', {}, d.name, ' ', el('span', { class: 'meta' }, d.appVersion ? `v${d.appVersion}` : '')),
                el('span', {}, d.protectionOn ? el('span', { class: 'pill mint' }, 'lock on') : el('span', { class: 'pill coral' }, 'lock off'), ' ', el('span', { class: 'meta' }, fmt.ago(d.lastSeenAt))),
              ),
            )
          : null,
        isStudent
          ? section('Study sessions', u.sessions, (s) =>
              el(
                'li',
                {},
                el('span', {}, el('strong', {}, s.subject), ' ', el('span', { class: 'meta' }, s.topics)),
                el(
                  'span',
                  { class: 'meta' },
                  `${fmt.minutes(s.studiedMinutes)} of ${s.plannedMinutes} min · ${s.adminUnlocked ? 'unlocked by admin' : s.status.toLowerCase().replace('_', ' ')} · ${fmt.dateTime(s.startedAt)}`,
                ),
              ),
            )
          : null,
        isStudent
          ? section('Exams', u.exams, (e) =>
              el(
                'li',
                {},
                el('span', {}, el('strong', {}, e.subject), ' ', el('span', { class: 'meta' }, e.source.toLowerCase())),
                el(
                  'span',
                  {},
                  e.passed === null || e.passed === undefined
                    ? el('span', { class: 'pill amber' }, e.status.toLowerCase())
                    : el('span', { class: `pill ${e.passed ? 'mint' : 'coral'}` }, `${Math.round(e.score ?? 0)}/${e.totalMarks} ${e.passed ? 'passed' : 'failed'}`),
                  ' ',
                  el('span', { class: 'meta' }, fmt.date(e.submittedAt ?? e.createdAt)),
                ),
              ),
            )
          : null,
      );
    } catch (e) {
      if (e.status !== 401) fill(body, errorBanner(e.message), el('button', { class: 'btn ghost', onclick: close }, 'Close'));
    }
  }

  show();
  // Live: redraw every 10 s, except while a dialog or a one-time password is on screen.
  const liveTimer = setInterval(() => {
    if (!document.hidden && !document.querySelector('.dialog') && !message.hasChildNodes()) show();
  }, LIVE_MS);
}

// ---------- study time ----------

let studyDays = 7;

function renderStudy(main, silent = false) {
  if (!silent) setLive(() => renderStudy(main, true));
  load(main, 'Study time', async () => {
    const data = await api(`/admin/study?days=${studyDays}`);
    const period = select(
      'Period',
      [['1', 'Last 24 hours'], ['7', 'Last 7 days'], ['30', 'Last 30 days'], ['0', 'All time']],
      String(studyDays),
      (v) => {
        studyDays = Number(v);
        renderStudy(main);
      },
    );
    const studied = data.students.filter((s) => s.minutes > 0);
    fill(
      main,
      pageHead('Study time', 'Who studied how long, and which subjects', el('span', { class: 'head-tools' }, liveBadge(), period)),
      el(
        'div',
        { class: 'tiles' },
        tile('Total studied', fmt.minutes(data.totalMinutes), `${studied.length} of ${data.students.length} students studied`, 'violet'),
        tile('Top subject', data.subjects[0]?.subject ?? '—', data.subjects[0] ? fmt.minutes(data.subjects[0].minutes) : 'no study yet', 'mint'),
        tile('Top student', studied[0]?.name ?? '—', studied[0] ? fmt.minutes(studied[0].minutes) : 'no study yet', 'amber'),
      ),
      el(
        'div',
        { class: 'grid-2' },
        el(
          'section',
          { class: 'card' },
          el('h2', {}, 'Students'),
          data.students.length === 0
            ? el('p', { class: 'empty' }, 'No students yet.')
            : el(
                'div',
                { class: 'table-wrap' },
                el(
                  'table',
                  {},
                  el('thead', {}, el('tr', {}, el('th', {}, 'Student'), el('th', { class: 'num' }, 'Studied'), el('th', { class: 'num' }, 'Sessions'), el('th', {}, 'Subjects'), el('th', {}, 'Last studied'))),
                  el(
                    'tbody',
                    {},
                    data.students.map((s) =>
                      el(
                        'tr',
                        { tabindex: 0, onclick: () => openUser(s.id), onkeydown: (e) => e.key === 'Enter' && openUser(s.id) },
                        el('td', { class: 'who' }, el('strong', {}, s.name), el('span', {}, s.contact ?? '')),
                        el('td', { class: 'num' }, el('strong', {}, fmt.minutes(s.minutes))),
                        el('td', { class: 'num' }, fmt.num(s.sessions)),
                        el('td', { class: 'muted' }, s.subjects.slice(0, 3).map((x) => `${x.subject} ${fmt.minutes(x.minutes)}`).join(' · ') || '—'),
                        el('td', { class: 'muted' }, s.lastStudiedAt ? fmt.ago(s.lastStudiedAt) : '—'),
                      ),
                    ),
                  ),
                ),
              ),
        ),
        el(
          'section',
          { class: 'card' },
          el('h2', {}, 'Subjects'),
          data.subjects.length === 0 ? el('p', { class: 'empty' }, 'No study yet.') : subjectBars(data.subjects),
        ),
      ),
    );
  }, silent);
}

// ---------- activity log ----------

const activityState = { kind: '', page: 1 };

function renderActivity(main, silent = false) {
  if (!silent) setLive(() => renderActivity(main, true));
  load(main, 'Activity log', async () => {
    const params = new URLSearchParams({ page: String(activityState.page), pageSize: '50' });
    if (activityState.kind) params.set('kind', activityState.kind);
    const data = await api(`/admin/activity?${params}`);
    const pages = Math.max(1, Math.ceil(data.total / data.pageSize));
    const kind = select('Event', [['', 'Everything'], ...Object.entries(EVENT_LABEL).map(([k, [label]]) => [k, label])], activityState.kind, (v) => {
      activityState.kind = v;
      activityState.page = 1;
      renderActivity(main);
    });
    const go = (delta) => {
      activityState.page += delta;
      renderActivity(main);
    };
    fill(
      main,
      pageHead('Activity log', 'Who signed in or out, and when, plus every admin action', el('span', { class: 'head-tools' }, liveBadge(), kind)),
      el(
        'section',
        { class: 'card' },
        data.events.length === 0
          ? el('p', { class: 'empty' }, 'Nothing recorded yet.')
          : el(
              'div',
              { class: 'table-wrap' },
              el(
                'table',
                {},
                el('thead', {}, el('tr', {}, el('th', {}, 'When'), el('th', {}, 'Account'), el('th', {}, 'What'), el('th', {}, 'Device / by'), el('th', {}, 'IP'))),
                el(
                  'tbody',
                  {},
                  data.events.map((e) =>
                    el(
                      'tr',
                      { tabindex: 0, onclick: () => openUser(e.user.id), onkeydown: (ev) => ev.key === 'Enter' && openUser(e.user.id) },
                      el('td', { class: 'muted nowrap' }, fmt.dateTime(e.createdAt)),
                      el('td', { class: 'who' }, el('strong', {}, e.user.name), el('span', {}, e.user.role.toLowerCase())),
                      el('td', {}, eventPill(e.kind), e.detail ? el('div', { class: 'meta' }, e.detail) : null),
                      el('td', { class: 'muted' }, e.actor ? `by ${e.actor}` : fmt.device(e.userAgent)),
                      el('td', { class: 'muted' }, e.ip ?? '—'),
                    ),
                  ),
                ),
              ),
            ),
        el(
          'div',
          { class: 'pager' },
          el('span', {}, `${fmt.num(data.total)} event${data.total === 1 ? '' : 's'} · page ${data.page} of ${pages}`),
          el(
            'span',
            { class: 'toolbar', style: 'margin:0' },
            el('button', { class: 'btn ghost small', disabled: data.page <= 1, onclick: () => go(-1) }, '← Newer'),
            el('button', { class: 'btn ghost small', disabled: data.page >= pages, onclick: () => go(1) }, 'Older →'),
          ),
        ),
      ),
    );
  }, silent);
}

// ---------- reports (AI content flagged by users) ----------

const REPORT_KIND = { TUTOR: 'AI helper answer', EXAM: 'Exam question', CALENDAR: 'Calendar import' };
const reportsState = { status: 'open' };

function renderReports(main, silent = false) {
  if (!silent) setLive(() => renderReports(main, true));
  load(main, 'Reports', async () => {
    const data = await api(`/admin/reports?status=${reportsState.status}`);
    const status = select('Show', [['open', 'To review'], ['resolved', 'Done'], ['all', 'All']], reportsState.status, (v) => {
      reportsState.status = v;
      renderReports(main);
    });
    fill(
      main,
      pageHead('Reports', 'AI answers and questions that users flagged as wrong or unsuitable', el('span', { class: 'head-tools' }, liveBadge(), status)),
      el(
        'section',
        { class: 'card' },
        data.reports.length === 0
          ? el('p', { class: 'empty' }, reportsState.status === 'open' ? 'Nothing to review. 🎉' : 'No reports here.')
          : el(
              'ul',
              { class: 'list' },
              data.reports.map((r) =>
                el(
                  'li',
                  { class: 'report' },
                  el(
                    'div',
                    { class: 'grow' },
                    el('div', {}, el('span', { class: 'pill amber' }, REPORT_KIND[r.kind] ?? r.kind), ' ', el('strong', {}, r.user.name), ' ', el('span', { class: 'meta' }, fmt.dateTime(r.createdAt))),
                    el('p', { class: 'report-text' }, r.content),
                    r.reason ? el('p', { class: 'meta' }, 'Reason: ', r.reason) : null,
                  ),
                  el(
                    'button',
                    {
                      class: r.resolvedAt ? 'btn ghost small' : 'btn small',
                      async onclick(e) {
                        e.target.disabled = true;
                        try {
                          await api(`/admin/reports/${encodeURIComponent(r.id)}`, { method: 'PATCH', body: { resolved: !r.resolvedAt } });
                          renderReports(main, true);
                        } catch (err) {
                          toast(err.message, 'err');
                          e.target.disabled = false;
                        }
                      },
                    },
                    r.resolvedAt ? 'Reopen' : 'Mark done',
                  ),
                ),
              ),
            ),
      ),
    );
  }, silent);
}

// ---------- settings ----------

const NUMBER_FIELDS = [
  ['minPassPercent', 'Lowest pass mark (%)', 'Students may choose a higher mark, never a lower one. At least 50.', 50, 100],
  ['minStudyMinutes', 'Shortest study session (min)', '', 1, 60],
  ['maxStudyMinutes', 'Longest study session (min)', '', 10, 600],
  ['earlyFinishPercent', 'Finish early after (% of time)', 'Share of the timer after which "finish early" opens the exam.', 0, 100],
  ['maxQuestions', 'Most questions per exam', '', 3, 50],
  ['examRetryCooldownSeconds', 'Wait before retrying a failed exam (s)', '0 lets students retry at once, with fresh questions.', 0, 3600],
  ['tutorDailyLimit', 'AI helper messages per day', 'Per student. 0 turns the helper off.', 0, 1000],
];

function renderSettings(main) {
  load(main, 'Settings', async () => {
    const saved = await api('/admin/settings');
    const draft = structuredClone(saved);
    const banner = el('div', { role: 'status' });
    const errors = {};

    const field = (key, label, help, control) => {
      errors[key] = el('div', { class: 'err' });
      return el('div', { class: 'field' }, el('label', { for: key }, label), control, help ? el('div', { class: 'help' }, help) : null, errors[key]);
    };

    const numberInputs = NUMBER_FIELDS.map(([key, label, help, min, max]) =>
      field(key, label, help, el('input', { class: 'input', id: key, type: 'number', min, max, step: 1, value: draft[key], oninput: (e) => (draft[key] = e.target.valueAsNumber) })),
    );

    const chips = el('div', { class: 'chips' });
    const drawChips = () =>
      fill(
        chips,
        draft.subjects.map((s, i) =>
          el('span', { class: 'chip' }, s, el('button', { type: 'button', 'aria-label': `Remove ${s}`, onclick: () => (draft.subjects.splice(i, 1), drawChips()) }, '×')),
        ),
      );
    drawChips();
    const newSubject = el('input', { class: 'input grow', id: 'subjects', placeholder: 'Add a subject', maxlength: 40 });
    const addSubject = () => {
      const value = newSubject.value.trim();
      if (value && !draft.subjects.some((s) => s.toLowerCase() === value.toLowerCase())) draft.subjects.push(value);
      newSubject.value = '';
      drawChips();
    };
    newSubject.addEventListener('keydown', (e) => e.key === 'Enter' && (e.preventDefault(), addSubject()));

    const announcement = el('textarea', { class: 'input', id: 'announcement', rows: 2, maxlength: 280, oninput: (e) => (draft.announcement = e.target.value) });
    announcement.value = draft.announcement ?? '';

    const save = el('button', { class: 'btn', type: 'submit' }, 'Save changes');
    errors.subjects = el('div', { class: 'err' });

    const form = el(
      'form',
      {
        async onsubmit(event) {
          event.preventDefault();
          Object.values(errors).forEach((e) => (e.textContent = ''));
          fill(banner);
          const patch = {};
          for (const key of Object.keys(draft)) {
            let value = draft[key];
            if (key === 'announcement') value = value && value.trim() ? value.trim() : null;
            if (JSON.stringify(value) !== JSON.stringify(saved[key])) patch[key] = value;
          }
          if (Object.keys(patch).length === 0) return fill(banner, el('div', { class: 'banner ok' }, 'Nothing to save.'));
          save.disabled = true;
          try {
            Object.assign(saved, await api('/admin/settings', { method: 'PATCH', body: patch }));
            fill(banner, el('div', { class: 'banner ok' }, 'Saved. Phones pick up the change within a minute.'));
          } catch (e) {
            for (const [key, messages] of Object.entries(e.fields ?? {})) {
              const target = errors[key.split('.')[0]];
              if (target) target.textContent = messages[0];
            }
            fill(banner, errorBanner(e.message));
          } finally {
            save.disabled = false;
          }
        },
      },
      el('section', { class: 'card' }, el('h2', {}, 'Exams and study'), el('div', { class: 'form-grid' }, numberInputs)),
      el(
        'section',
        { class: 'card', style: 'margin-top:16px' },
        el('h2', {}, 'AI'),
        el('label', { class: 'switch' }, el('input', { type: 'checkbox', checked: draft.aiEnabled, onchange: (e) => (draft.aiEnabled = e.target.checked) }), 'AI exams and study helper on'),
        el('p', { class: 'sub' }, 'When off, exams use the built-in practice questions and the helper is paused.'),
      ),
      el(
        'section',
        { class: 'card', style: 'margin-top:16px' },
        el('h2', {}, 'Subjects'),
        el('p', { class: 'sub', style: 'margin:-6px 0 12px' }, 'The list students pick from when they start a session.'),
        chips,
        el('div', { class: 'toolbar', style: 'margin:14px 0 0' }, newSubject, el('button', { class: 'btn ghost', type: 'button', onclick: addSubject }, 'Add')),
        errors.subjects,
      ),
      el('section', { class: 'card', style: 'margin-top:16px' }, field('announcement', 'Announcement', 'Shown as a banner in the app. Leave empty for none. Up to 280 characters.', announcement)),
      el('div', { class: 'actions' }, el('button', { class: 'btn ghost', type: 'button', onclick: () => renderSettings(main) }, 'Discard'), save),
    );

    fill(main, pageHead('Settings', 'Rules every student and parent gets'), banner, form);
  });
}

route();
