import { module, test } from 'qunit';
import { setupTest } from '@fleetbase/console/tests/helpers';

module('Unit | Service | intl', function (hooks) {
    setupTest(hooks);

    test('a shipped locale is applied as given', function (assert) {
        const intl = this.owner.lookup('service:intl');

        intl.setLocale('ru-RU');
        assert.deepEqual(intl.locale, ['ru-ru']);

        intl.setLocale(['uz-uz']);
        assert.deepEqual(intl.locale, ['uz-uz']);
    });

    test('a locale the console no longer ships falls back to English without being registered', function (assert) {
        const intl = this.owner.lookup('service:intl');

        intl.setLocale('fr-fr');

        assert.deepEqual(intl.locale, ['en-us']);
        assert.notOk(intl.locales.includes('fr-fr'), 'the language picker is not offered the dropped locale');
    });

    test('only the shipped locales of a list are kept', function (assert) {
        const intl = this.owner.lookup('service:intl');

        intl.setLocale(['mn-mn', 'uz-uz', 'de-de', 'en-us']);

        assert.deepEqual(intl.locale, ['uz-uz', 'en-us']);
    });

    test('the console ships English, Russian and Uzbek only', function (assert) {
        const intl = this.owner.lookup('service:intl');

        // The application route's default is spelled en-US; it must not register a second English.
        intl.setLocale(['en-US']);

        assert.deepEqual(intl.locale, ['en-us']);
        assert.deepEqual([...intl.locales].sort(), ['en-us', 'ru-ru', 'uz-uz']);
    });
});
