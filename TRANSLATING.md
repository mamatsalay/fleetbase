# Contributing to Fleetbase Translations

First off, thank you for considering contributing to Fleetbase translations! Your efforts help make Fleetbase accessible to a global audience. This guide will walk you through the process of adding or updating language translations for the Fleetbase platform and its various extensions.

## Understanding the Structure

Fleetbase is a modular system. The main application, known as Fleetbase Console, has its own set of translations. Additionally, each extension (like FleetOps or IAM) also contains its own translation files. This means that to provide a complete translation for a specific language, you may need to contribute to multiple repositories.

- **Main Application (`fleetbase/fleetbase`)**: Contains the core translation files for the Fleetbase Console.
- **Extensions/Modules**: Each extension has its own repository and its own set of translation files.

## File Format and Location

All translation files are in the **YAML** format (`.yaml` or `.yml`). The base language for all translations is American English (`en-us.yaml`).

- In the main `fleetbase/fleetbase` repository, the translation files are located at `./console/translations/`.
- In each extension repository, the translation files are located at `./translations/`.

Translation files are named using the language and region code. The console ships these languages:

- `en-us.yaml` (American English)
- `ru-ru.yaml` (Russian)
- `uz-uz.yaml` (Uzbek, Latin script)

Only these locales are built into the console. The allow-list is `includeLocales` in `./console/config/ember-intl.js`, and it also applies to extension translation files, so an extension's other languages are left out of the build. Any key missing from a supported language falls back to English.

### Extension strings translated in the console

Extensions ship their own translation files, and most have no Uzbek and incomplete Russian. The console fills the gaps in `./console/translations/extensions/<extension>/ru-ru.yaml` and `uz-uz.yaml`. Each file holds only the keys its extension leaves untranslated, under the same key paths as the extension's `en-us.yaml`.

ember-intl merges every translation file of a locale into one, and the console's files are merged after the extensions', so a key here wins over the extension's own. Keys the console's own `en-us.yaml` defines are left out: the console already owns those. When an extension update adds new keys, they show in English until they are added here.

## How to Contribute Translations

Follow these steps to contribute a new translation or update an existing one.

### Step 1: Fork and Clone the Repository

First, you need to fork the repository you want to contribute to. This could be the main `fleetbase/fleetbase` repository or one of the extension repositories. After forking, clone it to your local machine.

### Step 2: Create or Update a Language File

Navigate to the appropriate translations directory (`./console/translations/` or `./translations/`).

- **To add a new language**: Copy the `en-us.yaml` file and rename it to your target language code (e.g., `kk-kz.yaml`), then add that code to `includeLocales` in `./console/config/ember-intl.js`. Without that, the build leaves the language out.
- **To update an existing language**: Open the existing language file. You can compare it with `en-us.yaml` to find missing keys or phrases that need updating.

### Step 3: Translate the Content

Open the YAML file in a text editor. You will see a structure of nested keys and values.

```yaml
# Example from en-us.yaml
common:
  new: New
  create: Create
  delete-selected-count: Delete {count} Selected
```

When translating, you should:

- **Only translate the values**, not the keys. For example, in `new: New`, you would only translate `New`.
- **Keep placeholders intact**. Some phrases contain placeholders like `{count}` or `{resource}`. These should not be translated. They are used by the application to insert dynamic values.

Here is an example of the Uzbek translation for the keys above:

```yaml
# Example from uz-uz.yaml
common:
  new: Yangi
  create: Yaratish
  delete-selected-count: "{count} ta tanlanganni o'chirish"
```

A value that starts with a placeholder must be quoted, as above, or YAML reads it as a mapping.

### Step 4: Submit a Pull Request

Once you have finished translating, commit your changes and push them to your forked repository. Then, open a pull request to the original Fleetbase repository.

- Make sure your pull request has a clear title and description of the changes you made.
- If you are translating an extension, you may need to submit a pull request to the extension's repository. If your changes also affect the main console, a separate PR to the `fleetbase/fleetbase` repository might be necessary.

Your contribution will be reviewed by the Fleetbase team, and once approved, it will be merged into the project.

## Translation Repositories

Here is a list of the primary repositories that accept translation contributions:

| Repository                               | Translation Path              |
| ---------------------------------------- | ----------------------------- |
| [fleetbase/fleetbase][1]                 | `./console/translations/`     |
| [fleetbase/fleetops][2]                  | `./translations/`             |
| [fleetbase/dev-engine][3]                | `./translations/`             |
| [fleetbase/iam-engine][4]                | `./translations/`             |
| [fleetbase/pallet][5]                    | `./translations/`             |
| [fleetbase/ledger][6]                    | `./translations/`             |
| [fleetbase/registry-bridge][7]           | `./translations/`             |

[1]: https://github.com/fleetbase/fleetbase
[2]: https://github.com/fleetbase/fleetops
[3]: https://github.com/fleetbase/dev-engine
[4]: https://github.com/fleetbase/iam-engine
[5]: https://github.com/fleetbase/pallet
[6]: https://github.com/fleetbase/ledger
[7]: https://github.com/fleetbase/registry-bridge

Thank you again for your contribution to the Fleetbase community!
