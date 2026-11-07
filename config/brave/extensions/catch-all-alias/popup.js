/* global CA */
(async () => {
  const STATUS_SHOWN_MS = 1500;
  const $ = (id) => document.getElementById(id);

  async function activeHostname() {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    try {
      return new URL(tab.url).hostname;
    } catch (_) {
      // A page without a URL of its own, e.g. brave:// pages
      return '';
    }
  }

  const hostname = await activeHostname();
  const settings = await CA.getSettings();
  if (!hostname) {
    $('title').textContent = 'No website in the active tab';
    $('fresh').textContent = '–';
    return;
  }
  if (!settings.domain) {
    $('title').textContent = 'No domain set yet';
    $('fresh').textContent = 'Set your domain in the settings below.';
    $('copy').hidden = true;
    $('reroll').hidden = true;
    return;
  }
  const { base, site } = CA.parseHost(hostname);
  $('title').textContent = 'New alias for ' + base;

  function generate() {
    $('fresh').textContent = CA.buildAlias(settings, site);
  }
  generate();
  $('reroll').onclick = generate;

  async function copy(text) {
    await navigator.clipboard.writeText(text);
    $('status').textContent = 'Copied ✓';
    setTimeout(() => {
      $('status').textContent = '';
    }, STATUS_SHOWN_MS);
  }

  $('copy').onclick = async () => {
    const alias = $('fresh').textContent;
    await copy(alias);
    await CA.rememberAlias(base, alias);
    renderSaved();
  };

  function savedRow(alias) {
    const row = document.createElement('div');
    row.className = 'row';
    const code = document.createElement('code');
    code.textContent = alias;
    const button = document.createElement('button');
    button.textContent = 'Copy';
    button.onclick = () => copy(alias);
    row.append(code, button);
    return row;
  }

  async function renderSaved() {
    const list = (await CA.getAliases())[base] || [];
    $('savedSec').hidden = list.length === 0;
    const box = $('saved');
    box.textContent = '';
    for (const entry of list) {
      box.appendChild(savedRow(entry.alias));
    }
  }
  renderSaved();
})();
