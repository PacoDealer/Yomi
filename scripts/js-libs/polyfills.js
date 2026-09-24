// Spec-compliant URL / URLSearchParams (url.searchParams, object init, has/delete/forEach/iteration). JSBridge's
// old hand-written URL dropped query strings for most LNReader plugins (S125 harness).
import 'core-js/actual/url';
import 'core-js/actual/url-search-params';

// JavaScriptCore inside an app has no atob/btoa (the macOS `jsc` shell does, which hides the gap in desktop tests).
// cheerio's HTML-entity decoder needs atob at module init, and LNReader plugins use both. Imported first.
const CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

if (typeof globalThis.atob !== 'function') {
  globalThis.atob = function atob(input) {
    const str = String(input).replace(/[\s=]+/g, '');
    let out = '';
    let buffer = 0;
    let bits = 0;
    for (let i = 0; i < str.length; i++) {
      const value = CHARS.indexOf(str[i]);
      if (value < 0) throw new Error('atob: invalid base64');
      buffer = (buffer << 6) | value;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out += String.fromCharCode((buffer >> bits) & 0xff);
      }
    }
    return out;
  };
}

if (typeof globalThis.btoa !== 'function') {
  globalThis.btoa = function btoa(input) {
    const str = String(input);
    let out = '';
    for (let i = 0; i < str.length; i += 3) {
      const a = str.charCodeAt(i), b = str.charCodeAt(i + 1), c = str.charCodeAt(i + 2);
      if (a > 255 || b > 255 || c > 255) throw new Error('btoa: character out of range');
      const n = (a << 16) | ((b || 0) << 8) | (c || 0);
      out += CHARS[(n >> 18) & 63] + CHARS[(n >> 12) & 63]
        + (i + 1 < str.length ? CHARS[(n >> 6) & 63] : '=')
        + (i + 2 < str.length ? CHARS[n & 63] : '=');
    }
    return out;
  };
}

// TextEncoder / TextDecoder (UTF-8 only) — some LNReader plugins hash or decode text with them.
if (typeof globalThis.TextEncoder !== 'function') {
  globalThis.TextEncoder = class TextEncoder {
    get encoding() { return 'utf-8'; }
    encode(input = '') {
      const utf8 = unescape(encodeURIComponent(String(input)));
      const bytes = new Uint8Array(utf8.length);
      for (let i = 0; i < utf8.length; i++) bytes[i] = utf8.charCodeAt(i);
      return bytes;
    }
  };
}
if (typeof globalThis.TextDecoder !== 'function') {
  globalThis.TextDecoder = class TextDecoder {
    get encoding() { return 'utf-8'; }
    decode(input) {
      if (!input) return '';
      const bytes = input instanceof Uint8Array ? input : new Uint8Array(input.buffer || input);
      let binary = '';
      for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
      try { return decodeURIComponent(escape(binary)); } catch (e) { return binary; }
    }
  };
}

// setTimeout / clearTimeout — JSC has no event loop here. Plugins use them for short waits between requests;
// run the callback on the next microtask (the delay is not honoured).
if (typeof globalThis.setTimeout !== 'function') {
  let nextId = 1;
  const cancelled = new Set();
  globalThis.setTimeout = function setTimeout(fn, _ms, ...args) {
    const id = nextId++;
    Promise.resolve().then(() => { if (!cancelled.delete(id) && typeof fn === 'function') fn(...args); });
    return id;
  };
  globalThis.clearTimeout = function clearTimeout(id) { cancelled.add(id); };
  globalThis.setInterval = globalThis.setInterval || function () { return 0; };
  globalThis.clearInterval = globalThis.clearInterval || function () {};
}
