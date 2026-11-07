/* global CA */
(async () => {
  const $ = (id) => document.getElementById(id);
  const s = await CA.getSettings();
  $('domain').value = s.domain;
  $('pattern').value = s.pattern;
  $('randLen').value = s.randLen;
  $('onlyEmpty').checked = s.onlyEmpty;
  $('disabled').value = (s.disabledSites || []).join('\n');

  const current = () => ({
    domain: $('domain').value.trim().replace(/^@/, '').toLowerCase(),
    pattern: $('pattern').value.trim() || CA.DEFAULTS.pattern,
    randLen: Math.min(Math.max(parseInt($('randLen').value, 10) || 4, 2), 16),
    onlyEmpty: $('onlyEmpty').checked,
    disabledSites: $('disabled').value.split(/\s+/).map((x) => x.trim().toLowerCase()).filter(Boolean)
  });
  const preview = () => {
    const s = current();
    $('preview').textContent = s.domain ? CA.buildAlias(s, 'amazon') : '(set a domain first)';
  };
  ['domain', 'pattern', 'randLen'].forEach((id) => $(id).addEventListener('input', preview));
  preview();

  $('save').onclick = async () => {
    await chrome.storage.sync.set(current());
    $('saved').textContent = 'Saved ✓';
    setTimeout(() => ($('saved').textContent = ''), 1500);
  };

  async function renderRows() {
    const aliases = await CA.getAliases();
    const q = $('search').value.trim().toLowerCase();
    const rows = [];
    Object.entries(aliases).forEach(([base, list]) => list.forEach((a) => rows.push({ base, ...a })));
    rows.sort((a, b) => b.ts - a.ts);
    const tbody = $('rows');
    tbody.textContent = '';
    rows.filter((r) => !q || r.base.includes(q) || r.alias.includes(q)).forEach((r) => {
      const tr = document.createElement('tr');
      const td = (content) => { const t = document.createElement('td'); t.append(content); return t; };
      const code = document.createElement('code'); code.textContent = r.alias;
      const del = document.createElement('button'); del.textContent = 'Remove';
      del.onclick = async () => { await CA.forgetAlias(r.base, r.alias); renderRows(); };
      tr.append(td(r.base), td(code), td(new Date(r.ts).toLocaleDateString()), td(del));
      tbody.appendChild(tr);
    });
    if (!rows.length) {
      const tr = document.createElement('tr'); const t = document.createElement('td');
      t.colSpan = 4; t.className = 'hint'; t.textContent = 'No aliases saved yet.';
      tr.appendChild(t); tbody.appendChild(tr);
    }
  }
  $('search').addEventListener('input', renderRows);
  renderRows();

  const download = (name, text, type) => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([text], { type }));
    a.download = name; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };
  $('export').onclick = async () => download('catch-all-aliases.json', JSON.stringify(await CA.getAliases(), null, 2), 'application/json');
  $('exportCsv').onclick = async () => {
    const lines = ['website,alias,date'];
    Object.entries(await CA.getAliases()).forEach(([base, list]) =>
      list.forEach((a) => lines.push([base, a.alias, new Date(a.ts).toISOString().slice(0, 10)].join(','))));
    download('catch-all-aliases.csv', lines.join('\n'), 'text/csv');
  };
  $('importBtn').onclick = () => $('importFile').click();
  $('importFile').onchange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    try {
      const incoming = JSON.parse(await file.text());
      const aliases = await CA.getAliases();
      Object.entries(incoming).forEach(([base, list]) => {
        if (!Array.isArray(list)) return;
        const merged = [...(aliases[base] || []), ...list.filter((a) => a && typeof a.alias === 'string')];
        const seen = new Set();
        aliases[base] = merged.sort((a, b) => (b.ts || 0) - (a.ts || 0)).filter((a) => !seen.has(a.alias) && seen.add(a.alias));
      });
      await chrome.storage.local.set({ aliases });
      renderRows();
    } catch (err) {
      alert('Import failed: ' + err.message);
    }
  };
})();
