/* global CA */
(() => {
  if (window.__catchAllAlias) return;
  window.__catchAllAlias = true;

  const { base, site } = CA.parseHost(location.hostname);
  let settings = { ...CA.DEFAULTS };
  let aliases = {};
  let dismissedFor = null; // field the user closed the dropdown for

  const refresh = async () => {
    try {
      settings = await CA.getSettings();
      aliases = await CA.getAliases();
    } catch (_) { /* extension was reloaded */ }
  };
  refresh();
  chrome.storage.onChanged.addListener(refresh);

  const isDisabledHere = () =>
    (settings.disabledSites || []).some((s) => s && (base === s || location.hostname.endsWith('.' + s) || location.hostname === s));

  // ---------- Finding email fields ----------
  const EMAIL_RE = /e-?mail|mail-?adresse|correo|courriel/i;
  function isEmailField(el) {
    if (!(el instanceof HTMLInputElement) || el.disabled || el.readOnly) return false;
    const type = (el.getAttribute('type') || 'text').toLowerCase();
    if (type === 'email') return true;
    if (!['text', ''].includes(type)) return false;
    const ac = (el.getAttribute('autocomplete') || '').toLowerCase();
    if (ac.includes('email')) return true;
    if (/search|query/i.test(el.name + ' ' + el.id)) return false;
    const hints = [el.name, el.id, el.placeholder, el.getAttribute('aria-label'), el.getAttribute('data-testid')].join(' ');
    if (EMAIL_RE.test(hints)) return true;
    const label = el.labels && el.labels[0] ? el.labels[0].textContent : '';
    return EMAIL_RE.test(label || '');
  }

  // ---------- Filling in (works with React/Vue/Angular) ----------
  function fill(el, value) {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    el.focus();
    setter.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }

  // ---------- Dropdown (in a shadow DOM, so the page's CSS can't reach it) ----------
  const host = document.createElement('catch-all-alias');
  host.style.cssText = 'all: initial; position: fixed; z-index: 2147483647; display: none;';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `
    <style>
      :host { all: initial; }
      .box { font: 13px/1.35 system-ui, -apple-system, "Segoe UI", sans-serif; color: #111827; background: #fff;
             border: 1px solid #d1d5db; border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,.18); overflow: hidden; min-width: 290px; }
      .head { display:flex; align-items:center; gap:6px; padding: 7px 10px; background:#f3f4f6; color:#4b5563; font-size:11.5px; font-weight:600; letter-spacing:.02em; }
      .head .x { margin-left:auto; cursor:pointer; border:0; background:none; font-size:15px; color:#6b7280; padding:0 2px; line-height:1; }
      .item { display:flex; flex-direction:column; padding: 8px 10px; cursor:pointer; border-top:1px solid #f3f4f6; }
      .item:hover, .item.sel { background:#eff6ff; }
      .addr { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; color:#1d4ed8; word-break: break-all; }
      .tag { font-size: 11px; color:#6b7280; margin-top:1px; }
      .foot { display:flex; gap:12px; padding: 6px 10px; border-top:1px solid #e5e7eb; background:#fafafa; }
      .foot button { border:0; background:none; color:#2563eb; cursor:pointer; font: inherit; font-size:12px; padding:0; }
      .foot button.muted { color:#6b7280; margin-left:auto; }
      @media (prefers-color-scheme: dark) {
        .box { background:#1f2937; color:#f9fafb; border-color:#374151; }
        .head { background:#111827; color:#9ca3af; }
        .item { border-color:#374151; }
        .item:hover, .item.sel { background:#1e3a8a; }
        .addr { color:#93c5fd; }
        .tag { color:#9ca3af; }
        .foot { background:#111827; border-color:#374151; }
        .foot button { color:#93c5fd; }
      }
    </style>
    <div class="box">
      <div class="head">✉ Alias for ${base}<button class="x" title="Close (Esc)">×</button></div>
      <div class="list"></div>
      <div class="foot">
        <button class="reroll" title="New random part">↻ Reroll</button>
        <button class="muted off" title="No more suggestions on this site">Turn off here</button>
      </div>
    </div>`;
  const listEl = root.querySelector('.list');

  let current = null;   // the field the dropdown is open for
  let options = [];     // [{ alias, tag, isNew, random }]
  let selIdx = 0;

  function makeOptions() {
    const saved = (aliases[base] || []).slice(0, 3).map((a, i) => ({
      alias: a.alias,
      tag: i === 0 ? 'Last used on this site' : 'Used on this site before'
    }));
    const fresh = { alias: CA.buildAlias(settings, site), tag: 'New alias', isNew: true, random: true };
    const opts = saved.length ? [...saved, fresh] : [fresh];
    const plain = CA.buildAlias(settings, site, '{site}');
    if (!opts.some((o) => o.alias === plain) && settings.pattern !== '{site}') {
      opts.push({ alias: plain, tag: 'Without the random part (easier to guess)', isNew: true });
    }
    return opts;
  }

  function render() {
    listEl.textContent = '';
    options.forEach((o, i) => {
      const div = document.createElement('div');
      div.className = 'item' + (i === selIdx ? ' sel' : '');
      const a = document.createElement('span'); a.className = 'addr'; a.textContent = o.alias;
      const t = document.createElement('span'); t.className = 'tag'; t.textContent = o.tag;
      div.append(a, t);
      div.addEventListener('mouseenter', () => { selIdx = i; mark(); });
      div.addEventListener('click', () => choose(i));
      listEl.appendChild(div);
    });
  }
  const mark = () => [...listEl.children].forEach((c, i) => c.classList.toggle('sel', i === selIdx));

  function position() {
    if (!current || !current.isConnected) return close();
    const r = current.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) return close();
    const h = host.offsetHeight || 160;
    const w = Math.max(r.width, 290);
    const below = r.bottom + 4 + h <= window.innerHeight || r.top < h + 8;
    host.style.top = (below ? r.bottom + 4 : r.top - h - 4) + 'px';
    host.style.left = Math.max(4, Math.min(r.left, window.innerWidth - w - 4)) + 'px';
    root.querySelector('.box').style.width = w + 'px';
  }

  function open(el) {
    if (!settings.domain || isDisabledHere()) return;
    if (settings.onlyEmpty && el.value.trim()) return;
    if (dismissedFor === el) return;
    if (current === el && host.style.display !== 'none') return;
    current = el;
    options = makeOptions();
    selIdx = 0;
    render();
    if (!host.isConnected) document.documentElement.appendChild(host);
    host.style.display = 'block';
    position();
  }

  function close() {
    host.style.display = 'none';
    current = null;
  }

  async function choose(i) {
    const o = options[i];
    const el = current;
    if (!o || !el) return;
    close();
    dismissedFor = el;
    fill(el, o.alias);
    try { await CA.rememberAlias(base, o.alias); } catch (_) { /* ignore */ }
  }

  // Clicks in the dropdown mustn't take the focus from the field
  root.addEventListener('mousedown', (e) => e.preventDefault());
  root.querySelector('.x').addEventListener('click', () => { dismissedFor = current; close(); });
  root.querySelector('.reroll').addEventListener('click', () => {
    options = options.map((o) => (o.random ? { ...o, alias: CA.buildAlias(settings, site) } : o));
    render();
  });
  root.querySelector('.off').addEventListener('click', async () => {
    const list = [...new Set([...(settings.disabledSites || []), base])];
    await chrome.storage.sync.set({ disabledSites: list });
    close();
  });

  // ---------- Events ----------
  document.addEventListener('focusin', (e) => {
    const el = e.composedPath()[0];
    if (isEmailField(el)) open(el);
  }, true);

  document.addEventListener('mousedown', (e) => {
    const el = e.composedPath()[0];
    if (el === host) return;
    if (isEmailField(el) && el !== current) {
      if (dismissedFor === el) dismissedFor = null; // clicking it again reopens it
      setTimeout(() => open(el), 0);
    } else if (current && el !== current) {
      close();
    }
  }, true);

  document.addEventListener('focusout', (e) => {
    if (e.composedPath()[0] === current) setTimeout(() => {
      if (current && document.activeElement !== current && !current.matches(':focus')) close();
    }, 150);
  }, true);

  document.addEventListener('input', (e) => {
    if (e.composedPath()[0] === current && settings.onlyEmpty && current.value.trim()) close();
  }, true);

  document.addEventListener('keydown', (e) => {
    if (!current || host.style.display === 'none' || e.composedPath()[0] !== current) {
      // Alt+Shift+E opens the dropdown at the focused field, also a filled one
      if (e.altKey && e.shiftKey && e.code === 'KeyE') {
        const el = e.composedPath()[0];
        if (el instanceof HTMLInputElement) {
          e.preventDefault();
          dismissedFor = null;
          const prev = settings.onlyEmpty;
          settings.onlyEmpty = false; open(el); settings.onlyEmpty = prev;
        }
      }
      return;
    }
    if (e.key === 'ArrowDown') { selIdx = (selIdx + 1) % options.length; mark(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { selIdx = (selIdx - 1 + options.length) % options.length; mark(); e.preventDefault(); }
    else if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); choose(selIdx); }
    else if (e.key === 'Escape') { dismissedFor = current; close(); e.stopPropagation(); }
  }, true);

  window.addEventListener('scroll', () => current && position(), true);
  window.addEventListener('resize', () => current && position());

  // An email field may already have the focus when the page loads
  setTimeout(() => {
    const a = document.activeElement;
    if (isEmailField(a)) open(a);
  }, 300);
})();
