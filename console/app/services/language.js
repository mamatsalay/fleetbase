import LanguageService from '@fleetbase/ember-core/services/language';

// A locale's language named in that language, e.g. uz-uz is "O‘zbek".
const nativeLanguageName = (locale) => {
    const [code] = locale.split('-');
    try {
        const name = new Intl.DisplayNames([code], { type: 'language' }).of(code);
        return name.charAt(0).toLocaleUpperCase(code) + name.slice(1);
    } catch {
        return locale;
    }
};

export default class ConsoleLanguageService extends LanguageService {
    // ember-core names a locale after the first language its country lists, and countries list
    // their languages alphabetically, so uz-uz came out as "Russian". Name it by its own code.
    _findCountryDataForLocale(locale) {
        const country = super._findCountryDataForLocale(locale);
        const language = nativeLanguageName(locale);

        return country ? { ...country, language } : { language };
    }
}
