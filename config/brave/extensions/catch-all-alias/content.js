/* global CA */
(() => {
  if (window.__catchAllAlias) {
    return;
  }
  window.__catchAllAlias = true;

  const DROPDOWN_MIN_WIDTH = 290;
  // Before the dropdown has been laid out once
  const DROPDOWN_HEIGHT_GUESS = 160;
  const FIELD_GAP = 4;
  const SAVED_SHOWN = 3;
  // Long enough for a click in the dropdown to land before it closes
  const FOCUS_OUT_DELAY_MS = 150;
  // An email field may already have the focus when the page loads
  const INITIAL_FOCUS_DELAY_MS = 300;

  const { base, site } = CA.parseHost(location.hostname);
  let settings = { ...CA.DEFAULTS };
  let aliases = {};
  // The field the user closed the dropdown for
  let dismissedFor = null;

  async function refresh() {
    try {
      settings = await CA.getSettings();
      aliases = await CA.getAliases();
    } catch (_) {
      // The extension was reloaded: this old content script keeps what it had
    }
  }
  refresh();
  chrome.storage.onChanged.addListener(refresh);

  function isDisabledHere() {
    const hostname = location.hostname;
    const isSite = (disabled) => {
      return base === disabled || hostname === disabled || hostname.endsWith('.' + disabled);
    };
    return (settings.disabledSites || []).some((disabled) => disabled && isSite(disabled));
  }

  // ---------- Finding email fields ----------
  const EMAIL_RE = /e-?mail|mail-?adresse|correo|courriel/i;

  function isEditableInput(el) {
    return el instanceof HTMLInputElement && !el.disabled && !el.readOnly;
  }

  function hintsOf(el) {
    return [
      el.name,
      el.id,
      el.placeholder,
      el.getAttribute('aria-label'),
      el.getAttribute('data-testid')
    ].join(' ');
  }

  function labelOf(el) {
    if (el.labels && el.labels[0]) {
      return el.labels[0].textContent || '';
    }
    return '';
  }

  function isEmailField(el) {
    if (!isEditableInput(el)) {
      return false;
    }
    const type = (el.getAttribute('type') || 'text').toLowerCase();
    if (type === 'email') {
      return true;
    }
    if (!['text', ''].includes(type)) {
      return false;
    }
    const autocomplete = (el.getAttribute('autocomplete') || '').toLowerCase();
    if (autocomplete.includes('email')) {
      return true;
    }
    if (/search|query/i.test(el.name + ' ' + el.id)) {
      return false;
    }
    if (EMAIL_RE.test(hintsOf(el))) {
      return true;
    }
    return EMAIL_RE.test(labelOf(el));
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
      :host {
        all: initial;
      }
      .box {
        font: 13px/1.35 system-ui, -apple-system, "Segoe UI", sans-serif;
        color: #111827;
        background: #fff;
        border: 1px solid #d1d5db;
        border-radius: 10px;
        box-shadow: 0 10px 30px rgba(0,0,0,.18);
        overflow: hidden;
        min-width: ${DROPDOWN_MIN_WIDTH}px;
      }
      .head {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 7px 10px;
        background: #f3f4f6;
        color: #4b5563;
        font-size: 11.5px;
        font-weight: 600;
        letter-spacing: .02em;
      }
      .head .x {
        margin-left: auto;
        cursor: pointer;
        border: 0;
        background: none;
        font-size: 15px;
        color: #6b7280;
        padding: 0 2px;
        line-height: 1;
      }
      .item {
        display: flex;
        flex-direction: column;
        padding: 8px 10px;
        cursor: pointer;
        border-top: 1px solid #f3f4f6;
      }
      .item:hover, .item.sel {
        background: #eff6ff;
      }
      .addr {
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        font-size: 13px;
        color: #1d4ed8;
        word-break: break-all;
      }
      .tag {
        font-size: 11px;
        color: #6b7280;
        margin-top: 1px;
      }
      .foot {
        display: flex;
        gap: 12px;
        padding: 6px 10px;
        border-top: 1px solid #e5e7eb;
        background: #fafafa;
      }
      .foot button {
        border: 0;
        background: none;
        color: #2563eb;
        cursor: pointer;
        font: inherit;
        font-size: 12px;
        padding: 0;
      }
      .foot button.muted {
        color: #6b7280;
        margin-left: auto;
      }
      @media (prefers-color-scheme: dark) {
        .box {
          background: #1f2937;
          color: #f9fafb;
          border-color: #374151;
        }
        .head {
          background: #111827;
          color: #9ca3af;
        }
        .item {
          border-color: #374151;
        }
        .item:hover, .item.sel {
          background: #1e3a8a;
        }
        .addr {
          color: #93c5fd;
        }
        .tag {
          color: #9ca3af;
        }
        .foot {
          background: #111827;
          border-color: #374151;
        }
        .foot button {
          color: #93c5fd;
        }
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
  const box = root.querySelector('.box');

  // The field the dropdown is open for
  let current = null;
  // [{ alias, tag, isNew, random }]
  let options = [];
  let selIdx = 0;

  function isOpen() {
    return current !== null && host.style.display !== 'none';
  }

  function savedOptions() {
    const saved = (aliases[base] || []).slice(0, SAVED_SHOWN);
    return saved.map((entry, index) => {
      const tag = index === 0 ? 'Last used on this site' : 'Used on this site before';
      return { alias: entry.alias, tag };
    });
  }

  function makeOptions() {
    const fresh = { alias: CA.buildAlias(settings, site), tag: 'New alias', isNew: true, random: true };
    const result = [...savedOptions(), fresh];
    const plain = CA.buildAlias(settings, site, '{site}');
    const isPlainListed = result.some((option) => option.alias === plain);
    if (!isPlainListed && settings.pattern !== '{site}') {
      result.push({ alias: plain, tag: 'Without the random part (easier to guess)', isNew: true });
    }
    return result;
  }

  function markSelected() {
    [...listEl.children].forEach((child, index) => {
      child.classList.toggle('sel', index === selIdx);
    });
  }

  function optionElement(option, index) {
    const div = document.createElement('div');
    div.className = index === selIdx ? 'item sel' : 'item';
    const address = document.createElement('span');
    address.className = 'addr';
    address.textContent = option.alias;
    const tag = document.createElement('span');
    tag.className = 'tag';
    tag.textContent = option.tag;
    div.append(address, tag);
    div.addEventListener('mouseenter', () => {
      selIdx = index;
      markSelected();
    });
    div.addEventListener('click', () => choose(index));
    return div;
  }

  function render() {
    listEl.textContent = '';
    options.forEach((option, index) => {
      listEl.appendChild(optionElement(option, index));
    });
  }

  // Below the field, or above it where there's no room below
  function position() {
    if (!current || !current.isConnected) {
      close();
      return;
    }
    const field = current.getBoundingClientRect();
    if (field.width === 0 && field.height === 0) {
      close();
      return;
    }
    const height = host.offsetHeight || DROPDOWN_HEIGHT_GUESS;
    const width = Math.max(field.width, DROPDOWN_MIN_WIDTH);
    const fitsBelow = field.bottom + FIELD_GAP + height <= window.innerHeight;
    const fitsAbove = field.top >= height + 2 * FIELD_GAP;
    const top = fitsBelow || !fitsAbove ? field.bottom + FIELD_GAP : field.top - height - FIELD_GAP;
    const rightmost = window.innerWidth - width - FIELD_GAP;
    const left = Math.max(FIELD_GAP, Math.min(field.left, rightmost));
    host.style.top = top + 'px';
    host.style.left = left + 'px';
    box.style.width = width + 'px';
  }

  function shouldOpen(el) {
    if (!settings.domain || isDisabledHere()) {
      return false;
    }
    if (settings.onlyEmpty && el.value.trim()) {
      return false;
    }
    if (dismissedFor === el) {
      return false;
    }
    return !(current === el && isOpen());
  }

  function open(el) {
    if (!shouldOpen(el)) {
      return;
    }
    current = el;
    options = makeOptions();
    selIdx = 0;
    render();
    if (!host.isConnected) {
      document.documentElement.appendChild(host);
    }
    host.style.display = 'block';
    position();
  }

  // Also for a filled field, whatever onlyEmpty says
  function openAnyway(el) {
    const onlyEmpty = settings.onlyEmpty;
    settings.onlyEmpty = false;
    open(el);
    settings.onlyEmpty = onlyEmpty;
  }

  function close() {
    host.style.display = 'none';
    current = null;
  }

  function dismiss() {
    dismissedFor = current;
    close();
  }

  async function choose(index) {
    const option = options[index];
    const el = current;
    if (!option || !el) {
      return;
    }
    close();
    dismissedFor = el;
    fill(el, option.alias);
    try {
      await CA.rememberAlias(base, option.alias);
    } catch (_) {
      // The extension was reloaded: the field is filled, only the history misses it
    }
  }

  // Clicks in the dropdown mustn't take the focus from the field
  root.addEventListener('mousedown', (event) => event.preventDefault());
  root.querySelector('.x').addEventListener('click', dismiss);
  root.querySelector('.reroll').addEventListener('click', () => {
    options = options.map((option) => {
      if (option.random) {
        return { ...option, alias: CA.buildAlias(settings, site) };
      }
      return option;
    });
    render();
  });
  root.querySelector('.off').addEventListener('click', async () => {
    const list = [...new Set([...(settings.disabledSites || []), base])];
    await chrome.storage.sync.set({ disabledSites: list });
    close();
  });

  // ---------- Events ----------
  const target = (event) => event.composedPath()[0];

  function onFocusIn(event) {
    const el = target(event);
    if (isEmailField(el)) {
      open(el);
    }
  }

  function onMouseDown(event) {
    const el = target(event);
    if (el === host) {
      return;
    }
    if (isEmailField(el) && el !== current) {
      // Clicking a dismissed field again reopens it
      if (dismissedFor === el) {
        dismissedFor = null;
      }
      setTimeout(() => open(el), 0);
    } else if (current && el !== current) {
      close();
    }
  }

  function closeUnlessFocused() {
    if (!current) {
      return;
    }
    const isFocused = document.activeElement === current || current.matches(':focus');
    if (!isFocused) {
      close();
    }
  }

  function onFocusOut(event) {
    if (target(event) === current) {
      setTimeout(closeUnlessFocused, FOCUS_OUT_DELAY_MS);
    }
  }

  function onInput(event) {
    if (target(event) === current && settings.onlyEmpty && current.value.trim()) {
      close();
    }
  }

  // Alt+Shift+E opens the dropdown at the focused field, also a filled one
  function onShortcut(event) {
    if (!event.altKey || !event.shiftKey || event.code !== 'KeyE') {
      return;
    }
    const el = target(event);
    if (el instanceof HTMLInputElement) {
      event.preventDefault();
      dismissedFor = null;
      openAnyway(el);
    }
  }

  function moveSelection(step) {
    selIdx = (selIdx + step + options.length) % options.length;
    markSelected();
  }

  function onKeyDown(event) {
    if (!isOpen() || target(event) !== current) {
      onShortcut(event);
      return;
    }
    if (event.key === 'ArrowDown') {
      moveSelection(1);
      event.preventDefault();
    } else if (event.key === 'ArrowUp') {
      moveSelection(-1);
      event.preventDefault();
    } else if (event.key === 'Enter') {
      event.preventDefault();
      event.stopPropagation();
      choose(selIdx);
    } else if (event.key === 'Escape') {
      dismiss();
      event.stopPropagation();
    }
  }

  function repositionIfOpen() {
    if (current) {
      position();
    }
  }

  document.addEventListener('focusin', onFocusIn, true);
  document.addEventListener('mousedown', onMouseDown, true);
  document.addEventListener('focusout', onFocusOut, true);
  document.addEventListener('input', onInput, true);
  document.addEventListener('keydown', onKeyDown, true);
  window.addEventListener('scroll', repositionIfOpen, true);
  window.addEventListener('resize', repositionIfOpen);

  setTimeout(() => {
    const el = document.activeElement;
    if (isEmailField(el)) {
      open(el);
    }
  }, INITIAL_FOCUS_DELAY_MS);
})();
