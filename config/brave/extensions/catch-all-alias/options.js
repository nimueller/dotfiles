/* global CA */
(async () => {
  const SAVED_SHOWN_MS = 1500;
  const $ = (id) => document.getElementById(id);

  const stored = await CA.getSettings();
  $('domain').value = stored.domain;
  $('pattern').value = stored.pattern;
  $('randLen').value = stored.randLen;
  $('onlyEmpty').checked = stored.onlyEmpty;
  $('disabled').value = (stored.disabledSites || []).join('\n');

  function randLength() {
    const length = parseInt($('randLen').value, 10) || CA.DEFAULTS.randLen;
    return Math.min(Math.max(length, CA.RAND_LENGTH_MIN), CA.RAND_LENGTH_MAX);
  }

  function disabledSites() {
    return $('disabled').value
      .split(/\s+/)
      .map((site) => site.trim().toLowerCase())
      .filter(Boolean);
  }

  // The settings as the form shows them
  function current() {
    return {
      domain: CA.cleanDomain($('domain').value),
      pattern: $('pattern').value.trim() || CA.DEFAULTS.pattern,
      randLen: randLength(),
      onlyEmpty: $('onlyEmpty').checked,
      disabledSites: disabledSites()
    };
  }

  function preview() {
    const settings = current();
    if (settings.domain) {
      $('preview').textContent = CA.buildAlias(settings, 'amazon');
    } else {
      $('preview').textContent = '(set a domain first)';
    }
  }
  for (const id of ['domain', 'pattern', 'randLen']) {
    $(id).addEventListener('input', preview);
  }
  preview();

  $('save').onclick = async () => {
    await chrome.storage.sync.set(current());
    $('saved').textContent = 'Saved ✓';
    setTimeout(() => {
      $('saved').textContent = '';
    }, SAVED_SHOWN_MS);
  };

  // All aliases as rows, the newest first: [{ base, alias, ts }]
  function aliasRows(aliases) {
    const rows = [];
    for (const [base, list] of Object.entries(aliases)) {
      for (const entry of list) {
        rows.push({ base, ...entry });
      }
    }
    return rows.sort((a, b) => b.ts - a.ts);
  }

  function cell(content) {
    const td = document.createElement('td');
    td.append(content);
    return td;
  }

  function aliasRow(row) {
    const tr = document.createElement('tr');
    const code = document.createElement('code');
    code.textContent = row.alias;
    const remove = document.createElement('button');
    remove.textContent = 'Remove';
    remove.onclick = async () => {
      await CA.forgetAlias(row.base, row.alias);
      renderRows();
    };
    const date = new Date(row.ts).toLocaleDateString();
    tr.append(cell(row.base), cell(code), cell(date), cell(remove));
    return tr;
  }

  function emptyRow() {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 4;
    td.className = 'hint';
    td.textContent = 'No aliases saved yet.';
    tr.appendChild(td);
    return tr;
  }

  async function renderRows() {
    const rows = aliasRows(await CA.getAliases());
    const query = $('search').value.trim().toLowerCase();
    const matches = (row) => !query || row.base.includes(query) || row.alias.includes(query);
    const tbody = $('rows');
    tbody.textContent = '';
    for (const row of rows.filter(matches)) {
      tbody.appendChild(aliasRow(row));
    }
    if (rows.length === 0) {
      tbody.appendChild(emptyRow());
    }
  }
  $('search').addEventListener('input', renderRows);
  renderRows();

  function download(name, text, type) {
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([text], { type }));
    link.download = name;
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }

  $('export').onclick = async () => {
    const json = JSON.stringify(await CA.getAliases(), null, 2);
    download('catch-all-aliases.json', json, 'application/json');
  };

  $('exportCsv').onclick = async () => {
    const lines = ['website,alias,date'];
    for (const [base, list] of Object.entries(await CA.getAliases())) {
      for (const entry of list) {
        const date = new Date(entry.ts).toISOString().slice(0, 10);
        lines.push([base, entry.alias, date].join(','));
      }
    }
    download('catch-all-aliases.csv', lines.join('\n'), 'text/csv');
  };

  // The saved and the imported aliases of a site, the newest first and each
  // alias once
  function mergeAliases(saved, imported) {
    const valid = imported.filter((entry) => entry && typeof entry.alias === 'string');
    const merged = [...saved, ...valid].sort((a, b) => (b.ts || 0) - (a.ts || 0));
    const seen = new Set();
    return merged.filter((entry) => {
      if (seen.has(entry.alias)) {
        return false;
      }
      seen.add(entry.alias);
      return true;
    });
  }

  async function importAliases(file) {
    const incoming = JSON.parse(await file.text());
    const aliases = await CA.getAliases();
    for (const [base, list] of Object.entries(incoming)) {
      if (Array.isArray(list)) {
        aliases[base] = mergeAliases(aliases[base] || [], list);
      }
    }
    await chrome.storage.local.set({ aliases });
  }

  $('importBtn').onclick = () => $('importFile').click();
  $('importFile').onchange = async (event) => {
    const file = event.target.files[0];
    if (!file) {
      return;
    }
    try {
      await importAliases(file);
      renderRows();
    } catch (error) {
      alert('Import failed: ' + error.message);
    }
  };
})();
