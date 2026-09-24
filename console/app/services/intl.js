import IntlService from 'ember-intl/services/intl';
import translations from 'ember-intl/translations';

const FALLBACK_LOCALE = 'en-us';

const normalizeLocale = (locale) => String(locale).replace(/_/g, '-').trim().toLowerCase();

// The locales the build actually ships, as filtered by `includeLocales` in config/ember-intl.js.
const SUPPORTED_LOCALES = translations.map(([locale]) => normalizeLocale(locale));

/**
 * Keeps the console on the locales it ships.
 *
 * A user can still have a locale saved from before a language was dropped, and it is applied as
 * soon as the user loads. ember-intl would switch to it anyway, register it as a locale with no
 * translations and render every string as missing, and the language picker, which lists every
 * registered locale, would offer it again. Unsupported locales are dropped instead, falling back
 * to English when none are left.
 *
 * Locales are also normalized before they reach ember-intl, which registers `en-US` as a second,
 * empty locale beside `en-us` otherwise.
 */
export default class ConsoleIntlService extends IntlService {
    setLocale(locale) {
        const supported = [locale]
            .flat()
            .map(normalizeLocale)
            .filter((tag) => SUPPORTED_LOCALES.includes(tag));

        super.setLocale(supported.length ? supported : [FALLBACK_LOCALE]);
    }
}
