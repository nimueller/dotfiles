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

  const RAND_LENGTH_MIN = 2;
  const RAND_LENGTH_MAX = 16;
  // The longest local part an address may have (RFC 5321)
  const LOCAL_PART_MAX = 64;
  const ALIASES_PER_SITE = 10;

  // Two-part endings, where the site's name is one level further down (amazon.co.uk)
  const MULTI_TLD = new Set([
    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'com.au', 'net.au', 'org.au',
    'co.nz', 'co.jp', 'ne.jp', 'com.br', 'com.tr', 'co.at', 'or.at', 'gv.at',
    'co.za', 'com.mx', 'com.cn', 'com.ar', 'co.in', 'co.kr', 'com.sg', 'com.hk',
    'com.pl', 'com.es', 'co.il', 'com.ua'
  ]);

  // Without characters that are easy to mix up (0/o, 1/l/i)
  const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';

  function sanitize(text) {
    const name = String(text)
      .toLowerCase()
      .replace(/[^a-z0-9-]/g, '')
      .replace(/^-+|-+$/g, '');
    return name || 'site';
  }

  // Returns { base: "amazon.co.uk", site: "amazon" }
  function parseHost(hostname) {
    const host = String(hostname || '')
      .toLowerCase()
      .replace(/^www\d*\./, '')
      .replace(/\.$/, '');
    const parts = host.split('.');
    const isIpAddress = /^\d+$/.test(parts[parts.length - 1]);
    if (parts.length < 2 || isIpAddress) {
      return { base: host, site: sanitize(host) };
    }
    const lastTwo = parts.slice(-2).join('.');
    const hasTwoPartEnding = MULTI_TLD.has(lastTwo) && parts.length >= 3;
    const baseLength = hasTwoPartEnding ? 3 : 2;
    const base = parts.slice(-baseLength).join('.');
    return { base, site: sanitize(parts[parts.length - baseLength]) };
  }

  function rand(length) {
    const values = new Uint32Array(length);
    crypto.getRandomValues(values);
    return Array.from(values, (value) => ALPHABET[value % ALPHABET.length]).join('');
  }

  function randLength(settings) {
    const length = +settings.randLen || DEFAULTS.randLen;
    return Math.min(Math.max(length, RAND_LENGTH_MIN), RAND_LENGTH_MAX);
  }

  function cleanLocal(local) {
    return local
      .toLowerCase()
      .replace(/[^a-z0-9._+-]/g, '')
      .replace(/([._+-])\1+/g, '$1')
      .replace(/^[._+-]+|[._+-]+$/g, '')
      .slice(0, LOCAL_PART_MAX);
  }

  function cleanDomain(domain) {
    return String(domain)
      .trim()
      .replace(/^@/, '')
      .trim()
      .toLowerCase();
  }

  function buildAlias(settings, site, pattern) {
    const now = new Date();
    const year = String(now.getFullYear());
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const local = (pattern || settings.pattern)
      .replace(/\{site\}/g, site)
      .replace(/\{rand\}/g, () => rand(randLength(settings)))
      .replace(/\{yyyy\}/g, year)
      .replace(/\{yy\}/g, year.slice(2))
      .replace(/\{mm\}/g, month);
    return cleanLocal(local) + '@' + cleanDomain(settings.domain);
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
    const list = (aliases[base] || []).filter((entry) => entry.alias !== alias);
    list.unshift({ alias, ts: Date.now() });
    aliases[base] = list.slice(0, ALIASES_PER_SITE);
    await chrome.storage.local.set({ aliases });
  }

  async function forgetAlias(base, alias) {
    const aliases = await getAliases();
    if (!aliases[base]) {
      return;
    }
    aliases[base] = aliases[base].filter((entry) => entry.alias !== alias);
    if (aliases[base].length === 0) {
      delete aliases[base];
    }
    await chrome.storage.local.set({ aliases });
  }

  return {
    DEFAULTS,
    RAND_LENGTH_MIN,
    RAND_LENGTH_MAX,
    parseHost,
    buildAlias,
    cleanDomain,
    getSettings,
    getAliases,
    rememberAlias,
    forgetAlias
  };
})();
