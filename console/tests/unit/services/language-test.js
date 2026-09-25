import { module, test } from 'qunit';
import { setupTest } from '@fleetbase/console/tests/helpers';
import { settled } from '@ember/test-helpers';
import Service from '@ember/service';

// The lookup/countries rows the language picker is built from; countries list their languages alphabetically.
const COUNTRIES = [
    { cca2: 'US', emoji: '🇺🇸', languages: { eng: 'English' } },
    { cca2: 'RU', emoji: '🇷🇺', languages: { rus: 'Russian' } },
    { cca2: 'UZ', emoji: '🇺🇿', languages: { rus: 'Russian', uzb: 'Uzbek' } },
];

module('Unit | Service | language', function (hooks) {
    setupTest(hooks);

    hooks.beforeEach(function () {
        const context = this;
        this.countries = COUNTRIES;
        this.owner.register(
            'service:fetch',
            class extends Service {
                get() {
                    return Promise.resolve(context.countries.map((country) => ({ ...country })));
                }
            }
        );
    });

    test('each locale is offered under its own language, not its country’s first', async function (assert) {
        const language = this.owner.lookup('service:language');
        await settled();

        const { availableLocales } = language;
        assert.deepEqual(Object.keys(availableLocales).sort(), ['en-us', 'ru-ru', 'uz-uz']);
        assert.strictEqual(availableLocales['en-us'].language, 'English');
        assert.strictEqual(availableLocales['ru-ru'].language, 'Русский');
        assert.strictEqual(availableLocales['uz-uz'].language, 'O‘zbek');
        assert.strictEqual(availableLocales['uz-uz'].emoji, '🇺🇿', 'the country’s flag is kept');
    });

    test('a locale whose country the lookup lacks is still named', async function (assert) {
        this.countries = COUNTRIES.filter((country) => country.cca2 !== 'UZ');
        const language = this.owner.lookup('service:language');
        await settled();

        assert.deepEqual(language.availableLocales['uz-uz'], { language: 'O‘zbek' });
    });
});
