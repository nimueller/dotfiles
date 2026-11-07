/* global CA */
(async () => {
  const $ = (id) => document.getElementById(id);
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  let hostname = '';
  try { hostname = new URL(tab.url).hostname; } catch (_) { /* e.g. brave:// pages */ }

  const settings = await CA.getSettings();
  if (!hostname) {
    $('title').textContent = 'No website in the active tab';
    $('fresh').textContent = '–';
    return;
  }
  if (!settings.domain) {
    $('title').textContent = 'No domain set yet';
    $('fresh').textContent = 'Set your domain in the settings below.';
    $('copy').hidden = $('reroll').hidden = true;
    return;
  }
  const { base, site } = CA.parseHost(hostname);
  $('title').textContent = 'New alias for ' + base;

  const gen = () => { $('fresh').textContent = CA.buildAlias(settings, site); };
  gen();
  $('reroll').onclick = gen;

  const copy = async (text) => {
    await navigator.clipboard.writeText(text);
    $('status').textContent = 'Copied ✓';
    setTimeout(() => ($('status').textContent = ''), 1500);
  };
  $('copy').onclick = async () => {
    const alias = $('fresh').textContent;
    await copy(alias);
    await CA.rememberAlias(base, alias);
    renderSaved();
  };

  async function renderSaved() {
    const list = (await CA.getAliases())[base] || [];
    $('savedSec').hidden = !list.length;
    const box = $('saved');
    box.textContent = '';
    list.forEach((a) => {
      const row = document.createElement('div'); row.className = 'row';
      const c = document.createElement('code'); c.textContent = a.alias;
      const b = document.createElement('button'); b.textContent = 'Copy'; b.onclick = () => copy(a.alias);
      row.append(c, b); box.appendChild(row);
    });
  }
  renderSaved();
})();
