/**
 * Tiny string table lookup with {param} substitution and English fallback.
 */
export class I18n {
  /**
   * @param {object} strings parsed strings.json ({ sv: {...}, en: {...} })
   * @param {string} lang initial language code
   */
  constructor(strings, lang) {
    this.strings = strings;
    this.lang = strings[lang] ? lang : 'en';
  }

  /** Picks Swedish for Swedish-speaking browsers, English otherwise. */
  static detect(strings) {
    const langs = (globalThis.navigator?.languages ?? [globalThis.navigator?.language ?? 'en']).map((l) => l.slice(0, 2));
    return langs.find((l) => strings[l]) ?? 'en';
  }

  setLanguage(lang) { if (this.strings[lang]) this.lang = lang; }

  /**
   * @param {string} key
   * @param {object} [params]
   */
  t(key, params) {
    let s = this.strings[this.lang]?.[key] ?? this.strings.en?.[key] ?? key;
    if (params) for (const [k, v] of Object.entries(params)) s = s.replaceAll(`{${k}}`, String(v));
    return s;
  }
}
