# Fleetbase Scripts

This directory contains project-level utilities for local development and setup. Run all commands from the repository root unless a command says otherwise.

## `package-linker.mjs`

`flb-package-linker` manages local Fleetbase package links for extension development. It updates the Console npm manifest, API Composer repositories, and Console pnpm workspace settings so linked extension packages and shared Ember packages resolve from `packages/*`.

Use this when working on an extension such as FleetOps and you need local changes from `packages/fleetops`, `packages/ember-ui`, `packages/ember-core`, or `packages/fleetops-data` to show up in the host app.

The linker only treats a package as a Fleetbase extension when either:

- its `package.json` has `fleetbase-extension` in `keywords`
- it has an `extension.json` manifest

The only non-extension packages supported for shared dependency linking are `@fleetbase/ember-core`, `@fleetbase/ember-ui`, `@fleetbase/fleetops-data`, and the backend-only `fleetbase/core-api`.

### Install as a Global CLI

From the repository root:

```sh
npm link
```

Or from this directory:

```sh
cd scripts
npm link
```

After that, use:

```sh
flb-package-linker --help
flb-package-linker status
```

Without global linking, run the script directly:

```sh
node scripts/package-linker.mjs status
```

### Common Commands

List packages discovered under `packages/*`:

```sh
flb-package-linker list
```

Show currently linked packages and shared dependency resolution:

```sh
flb-package-linker status
```

Check for missing local symlinks or duplicate Fleetbase package versions in `console/pnpm-lock.yaml`:

```sh
flb-package-linker doctor
```

Preview FleetOps linking without changing files:

```sh
flb-package-linker enable fleetops --shared ember-core ember-ui fleetops-data --dry-run
```

Enable FleetOps local development links:

```sh
flb-package-linker enable fleetops --shared ember-core ember-ui fleetops-data
flb-package-linker install
```

Enable multiple extensions at once:

```sh
flb-package-linker enable fleetops pallet --shared ember-core ember-ui fleetops-data
flb-package-linker install
```

Run the install/update step for specific extensions:

```sh
flb-package-linker install fleetops pallet
```

Preview the install/update commands without running them:

```sh
flb-package-linker install --dry-run
```

Reset all local development links managed by the linker:

```sh
flb-package-linker reset
flb-package-linker install
```

Preview a full reset without changing files:

```sh
flb-package-linker reset --dry-run
```

Enable only a shared frontend package:

```sh
flb-package-linker enable-shared ember-ui
flb-package-linker install
```

Enable the backend-only Core API package:

```sh
flb-package-linker enable-shared core-api
flb-package-linker install core-api
```

Disable local links and restore saved registry ranges:

```sh
flb-package-linker disable fleetops pallet
flb-package-linker disable-shared ember-core ember-ui fleetops-data core-api
flb-package-linker install fleetops pallet core-api
```

Run installs automatically after enabling:

```sh
flb-package-linker enable fleetops --shared ember-core ember-ui fleetops-data --install
```

### What It Changes

Depending on the command, `flb-package-linker` may update:

- `console/package.json`
- `console/pnpm-workspace.yaml`
- `console/.npmrc`
- `api/composer.json`
- `.fleetbase-dev-links.json`

The `.fleetbase-dev-links.json` file stores original dependency ranges so links can be reversed. It is ignored by git.

For pnpm, the linker moves non-auth `public-hoist-pattern[]` settings from `console/.npmrc` into `console/pnpm-workspace.yaml`, keeps registry auth in `.npmrc`, and sets workspace linking options for local shared packages.

## `docker-install.sh`

`docker-install.sh` is the interactive Fleetbase Docker setup wizard. It checks required local tools, asks for core environment settings, generates local configuration, and guides Docker Compose setup.

Run the interactive wizard:

```sh
bash scripts/docker-install.sh
```

Run with defaults for non-interactive environments:

```sh
bash scripts/docker-install.sh --non-interactive
```

Non-interactive mode binds to `localhost` in development mode. To install unattended on a server, set its address (and optionally the environment and app name) instead:

```sh
FLEETBASE_HOST=203.0.113.10 FLEETBASE_ENVIRONMENT=development FLEETBASE_APP_NAME=Fleetbase \
  bash scripts/docker-install.sh --non-interactive
```

The script expects Docker, Docker Compose v2, git, and OpenSSL to be available. It warns when common Fleetbase ports are already in use but does not treat that as a hard failure.

## `local-start.sh`

`local-start.sh` runs Fleetbase on your own computer (macOS or Linux) with Docker, in one command:

```sh
bash scripts/local-start.sh
```

On the first run it checks that Docker is running (on macOS it starts Docker Desktop or OrbStack if needed) and has at least 4 GB of memory, that there's disk space and ports 4200, 8000, 3306 and 38000 are free, then installs with `docker-install.sh --non-interactive`. The first install takes 15-30 minutes. It then waits for the console and opens http://localhost:4200.

Later runs don't install again (new credentials would no longer match the existing database); they start the containers:

```sh
bash scripts/local-start.sh            # start
bash scripts/local-start.sh --stop     # stop, keeping the data
git pull && bash scripts/local-start.sh --rebuild   # update: pull the API image, rebuild the console, migrate
bash scripts/local-start.sh --reset    # delete the install and its database, then start over
```

On Apple Silicon the websocket image only exists for x86 and runs under emulation; turning on "Use Rosetta for x86/amd64 emulation" in Docker Desktop makes it faster.

## `azure-create-vm.sh`

`azure-create-vm.sh` creates an Azure VM that runs Fleetbase with Docker Compose. It needs the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged in with `az login`:

```sh
bash scripts/azure-create-vm.sh --location westeurope
```

Everything goes into one resource group (`fleetbase-rg` by default):

- a network security group that allows SSH from your current IP only and ports 4200 (console), 8000 (API) and 38000 (websockets) from anywhere; MySQL stays closed
- a static public IP, so the address the install is configured with survives stopping and starting the VM
- an Ubuntu 24.04 VM (`Standard_B2s`, 4 GB RAM, 64 GB Standard SSD by default) that on first boot adds swap, installs Docker, clones the repository and runs `docker-install.sh --non-interactive` on its public address

The first install takes 15-30 minutes; the script waits for the console to answer and prints its URL. Fleetbase runs over plain HTTP in development mode.

Useful options (see `--help` for all of them):

- `--size Standard_B2ms` for 8 GB RAM
- `--dns-label <label>` to serve Fleetbase at `<label>.<region>.cloudapp.azure.com` instead of the bare IP
- `--branch <name>` to deploy a branch other than `main`
- `--auto-shutdown 2200` to stop the VM every day at that UTC time and save credit

Stop the VM with `az vm deallocate -g fleetbase-rg -n fleetbase-vm` when you aren't using it, and remove everything with `az group delete -n fleetbase-rg`.

## Validation

Check the package linker script:

```sh
node --check scripts/package-linker.mjs
node --test scripts/package-linker.test.mjs
```

Check shell syntax for the Docker installer:

```sh
bash -n scripts/docker-install.sh
```

Check shell syntax for the Azure VM script:

```sh
bash -n scripts/azure-create-vm.sh
```

Check shell syntax for the local start script:

```sh
bash -n scripts/local-start.sh
```
