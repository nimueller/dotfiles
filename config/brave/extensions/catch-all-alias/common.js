// Shared by the content script, the popup and the options page.
/* exported CA */
var CA = (() => {
  const DEFAULTS = {
    // Empty until set on the options page: no suggestions before that
    domain: '',
    pattern: '{site}.{rand}',
    randLen: 4,
    onlyEmpty: true,
    disabledSites: []
  };

  // Two-part endings, where the site's name is one level further down (amazon.co.uk)
  const MULTI_TLD = new Set([
    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'com.au', 'net.au', 'org.au',
    'co.nz', 'co.jp', 'ne.jp', 'com.br', 'com.tr', 'co.at', 'or.at', 'gv.at',
    'co.za', 'com.mx', 'com.cn', 'com.ar', 'co.in', 'co.kr', 'com.sg', 'com.hk',
    'com.pl', 'com.es', 'co.il', 'com.ua'
  ]);

  // Returns { base: "amazon.co.uk", site: "amazon" }
  function parseHost(hostname) {
    const host = String(hostname || '').toLowerCase().replace(/^www\d*\./, '').replace(/\.$/, '');
    const p = host.split('.');
    if (p.length < 2 || /^\d+$/.test(p[p.length - 1])) {
      return { base: host, site: sanitize(host) };
    }
    const last2 = p.slice(-2).join('.');
    const n = MULTI_TLD.has(last2) && p.length >= 3 ? 3 : 2;
    const base = p.slice(-n).join('.');
    return { base, site: sanitize(p[p.length - n]) };
  }

  function sanitize(s) {
    return String(s).toLowerCase().replace(/[^a-z0-9-]/g, '').replace(/^-+|-+$/g, '') || 'site';
  }

  // Without characters that are easy to mix up (0/o, 1/l/i)
  const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';
  function rand(n) {
    const buf = new Uint32Array(n);
    crypto.getRandomValues(buf);
    return Array.from(buf, (x) => ALPHABET[x % ALPHABET.length]).join('');
  }

  function cleanLocal(local) {
    return local
      .toLowerCase()
      .replace(/[^a-z0-9._+-]/g, '')
      .replace(/([._+-])\1+/g, '$1')
      .replace(/^[._+-]+|[._+-]+$/g, '')
      .slice(0, 64);
  }

  function buildAlias(settings, site, pattern) {
    const d = new Date();
    const local = (pattern || settings.pattern)
      .replace(/\{site\}/g, site)
      .replace(/\{rand\}/g, () => rand(Math.min(Math.max(+settings.randLen || 4, 2), 16)))
      .replace(/\{yyyy\}/g, String(d.getFullYear()))
      .replace(/\{yy\}/g, String(d.getFullYear()).slice(2))
      .replace(/\{mm\}/g, String(d.getMonth() + 1).padStart(2, '0'));
    return cleanLocal(local) + '@' + String(settings.domain).replace(/^@/, '').trim().toLowerCase();
  }

  async function getSettings() {
    return chrome.storage.sync.get(DEFAULTS);
  }

  // Aliases used so far: { "amazon.de": [{ alias, ts }, ...] } in storage.local
  async function getAliases() {
    const { aliases } = await chrome.storage.local.get({ aliases: {} });
    return aliases;
  }

  async function rememberAlias(base, alias) {
    const aliases = await getAliases();
    const list = (aliases[base] || []).filter((a) => a.alias !== alias);
    list.unshift({ alias, ts: Date.now() });
    aliases[base] = list.slice(0, 10);
    await chrome.storage.local.set({ aliases });
  }

  async function forgetAlias(base, alias) {
    const aliases = await getAliases();
    if (!aliases[base]) return;
    aliases[base] = aliases[base].filter((a) => a.alias !== alias);
    if (!aliases[base].length) delete aliases[base];
    await chrome.storage.local.set({ aliases });
  }

  return { DEFAULTS, parseHost, buildAlias, getSettings, getAliases, rememberAlias, forgetAlias };
})();
