# Dev Container

A VSCode Dev Container designed to create a secure, isolated environment in which to run automomous agents. It does **not** run the `docker compose` stack — the stack runs on the host. Running the stack inside the container would require mounting `/var/run/docker.sock`, which would give any process in the container — including an autonomous agent — full control over Docker on the host machine. Instead, the container connects to host services via `host.docker.internal`.

This repo is meant to be vendored into other projects (e.g. as a git submodule). It does not ship a single fixed `devcontainer.json`/`Dockerfile` — it ships a **generator** that produces those files from a project-specific answers file, so every consuming project gets the same security hardening with only its real differences (toolchain versions, extra files, extra hosts, etc.) varying.

Everything in this repo is the vendored, read-only core (`generate.sh`, `lib/`, `schema/`, `examples/`, `templates/`). The only files that land in a consuming project are whatever `generate.sh` writes into `--out-dir` (default `.devcontainer/`) — including the answers file itself, whether you authored it yourself or answered the interactive prompts.

## Install

Vendor this repo as a git submodule in the consuming project:

```bash
git submodule add <this-repo-url> external/dev-container-config
git submodule update --init --recursive
```

Unlike some vendored tools, nothing here hardcodes that path — `generate.sh` resolves its own location at runtime via `BASH_SOURCE`, so you can vendor it anywhere. `external/dev-container-config` is just the convention used throughout this README and in the shipped examples.

A fresh clone of a project that vendors this needs:

```bash
git clone --recurse-submodules <project-url>
# or, if already cloned:
git submodule update --init --recursive
```

## Generating a devcontainer for your project

Run these from your project's root (not from inside this submodule) so `--out-dir` (default `.devcontainer/`) and any relative paths in your answers file resolve against your project:

```bash
# Non-interactive: load every answer from a file (CI-friendly, reproducible)
./external/dev-container-config/generate.sh --answers .devcontainer/devcontainer.answers.json

# Interactive: answer prompts, including optional bind mounts
./external/dev-container-config/generate.sh

# Write somewhere other than ./.devcontainer, or force-overwrite hand-edited output
./external/dev-container-config/generate.sh --answers .devcontainer/devcontainer.answers.json --out-dir .devcontainer --force
```

Both modes write `devcontainer.json` and `Dockerfile` into `--out-dir` (default `.devcontainer/`). Start from [`external/dev-container-config/examples/minimal.answers.json`](examples/minimal.answers.json) or [`external/dev-container-config/examples/full.answers.json`](examples/full.answers.json) and see [`external/dev-container-config/schema/answers.schema.json`](schema/answers.schema.json) for every field.

Interactive mode can add multiple bind mounts. For each mount, enter a host path relative to the workspace, an absolute container path, and whether it should be read-only; the first mount defaults to `data` → `/workspace/data`, read-only.

`generate.sh` also saves the resolved answers JSON into `--out-dir` so it's never only a throwaway temp file:
- `--answers <file>` copies that file in under its own basename (e.g. `devcontainer.answers.json`) — skipped if it's already there.
- Interactive mode saves the collected answers as `devcontainer.answers.json`.
- Paths entered for project files are saved relative to that answers file, so the saved answers can be reused from another checkout.
- If an answers file of that name already exists in `--out-dir` and its contents differ from the newly generated one, the existing file is renamed to `<name>.bak.<UTC timestamp>` before the new one is written — nothing is silently overwritten.

The generated `devcontainer.json`/`Dockerfile` headers cite this saved copy as their source, so future regenerations have a durable, reviewable file to point `--answers` at.

**Generated files are not meant to be hand-edited.** Each one carries a header comment with a content hash. Re-running `generate.sh`:
- Silently overwrites the file if it still matches that hash (untouched since the last generation).
- If the file was hand-edited, leaves it alone and writes the new output to `devcontainer.json.new` / `Dockerfile.new` instead, so you can merge manually. `--force` skips this check and always overwrites.

If something a project needs isn't expressible in the answers file, that's a signal to add a field to the schema — not to hand-edit the generated output.

## Testing

```bash
./tests/run.sh              # unit tests + real docker build/run checks
./tests/run.sh --no-docker  # unit tests only (no docker required)
```

`tests/unit/` exercises the renderers and jq filters directly (fast, bash + jq only). `tests/docker/` exercises bootstrap selection and `npm-guard.sh` in real containers — skipped automatically if docker isn't installed/running.

Docker tests exercise bootstrap selection without network access using the
`node:22` image. To also test real pnpm resolution, set
`DCC_TEST_IMAGE=<generated-image> ./tests/run.sh`. That image must use the
example's 14-day policy and `ignore-scripts=true`, with the default `vscode`
user. The runtime fixture serves a local registry and verifies global CLI and
nested UI installs, transitive dependency age filtering, missing timestamps,
and suppression of install scripts.

### Layout of this repo

| Path | Purpose |
|---|---|
| `generate.sh` | Entry point — parses args, loads/collects answers, renders output |
| `lib/` | Generator implementation (bash + `jq`) — toolchain recipes, renderers, hash/conflict handling, file copying |
| `schema/answers.schema.json` | Documents every answers-file field |
| `examples/*.answers.json` | Starting points to copy into a consuming project |
| `templates/npm-guard.sh` | Built-in file; copied automatically when `dockerfileBuild.toolchains.pnpm` is set (or via `dockerfileBuild.files[]`) |
| `templates/install-pnpm.sh` | Bootstraps supported npm/pnpm versions when `dockerfileBuild.toolchains.pnpm` is set |
| `templates/install-package-manager.cjs` | Selects eligible package-manager releases, checks Node compatibility, installs and records selections |
| `tests/` | Test suite — see [Testing](#testing) |

## Security Overview

### How the container confines an autonomous agent

An autonomous agent running inside this container operates within several overlapping boundaries that prevent it from affecting the host machine or escaping its sandbox:

| Boundary | Mechanism |
|---|---|
| No Docker control | `/var/run/docker.sock` is not mounted — the agent cannot start, stop, or inspect containers on the host |
| No privilege escalation | `--security-opt no-new-privileges` blocks setuid binaries from gaining elevated rights |
| Minimal Linux capabilities | `--cap-drop ALL` then only `CHOWN`, `SETUID/SETGID`, `DAC_OVERRIDE`, `FOWNER` re-added — the full list an agent can operate with is auditable |
| Root locked | `passwd -l root` in `postCreateCommand`; `vscode` user has no `sudo` |
| Read-only data mounts | `data/` is overlaid read-only (`EROFS`) — an agent can read reference data but cannot modify it |
| Registry isolation | Public npm registries are null-routed; packages must come from the internal registry |
| Non-root user | Container runs as `vscode` (UID 1000) — writes outside the mounted workspace are rejected by the filesystem |

The combination means an agent can build, test, and deploy to the host's compose stack via `host.docker.internal`, but it cannot reconfigure the host OS, install new daemons, pull arbitrary packages from the internet, or lateral-move into other containers.

### Docker Desktop security (update policy)

Docker Desktop bundles its own LinuxKit VM kernel — it is not updated independently of Docker Desktop itself. Your Docker Desktop upgrade cadence **is** your Linux VM kernel patch cadence.

Running an outdated version carries real CVE exposure across multiple components. The bundled `runc` (the low-level container runtime) has historically been the source of critical vulnerabilities — CVE-2019-5736, for example, allowed a process inside a container to overwrite the host `runc` binary and achieve a full container escape with no special privileges required. `containerd`, the Moby engine, and the LinuxKit kernel each have their own CVE track. An old Docker Desktop version can simultaneously carry unpatched flaws in all of these layers, and because public exploit code is often available shortly after disclosure, the window between a CVE being published and active exploitation in the wild is narrow.

**Hold policy:** Wait at least 14 days after a release before upgrading. Before updating, check:

- [github.com/docker/for-mac/releases](https://github.com/docker/for-mac/releases) — community regression reports appear quickly in the Issues tab
- [docs.docker.com/desktop/release-notes](https://docs.docker.com/desktop/release-notes/) — official changelog
- Docker Security Advisories — any published CVEs against the release itself

**Installer verification:** Docker publishes SHA256 checksums. Verify the download before installing:

```bash
shasum -a 256 Docker.dmg
# compare output against the checksum published on docs.docker.com
```

**Other notes:**

- `DOCKER_CONTENT_TRUST=1` verifies image signatures, not the Docker Desktop binary itself — both checks are complementary
- Monitor Docker's GitHub for unusual commits; supply-chain attacks sometimes surface in diffs before an advisory is published
- Renovate's `minimumReleaseAge` automates the hold policy for Docker image dependencies inside the repo (see [Dependency update automation](#dependency-update-automation) below)

### Dependency update automation (Renovate)

[Renovate](https://github.com/apps/renovate) is a GitHub App (run by Mend in GitHub's infrastructure, not locally) that opens pull requests to bump dependency versions and respects a minimum release age. Without it, dependency versions drift silently — security patches land in upstream packages but your lock file never changes until someone manually bumps them. Renovate surfaces every update as a reviewable PR, creating an audit trail and ensuring CVE patches reach your repo promptly. The `minimumReleaseAge` hold prevents merging a new version before the community has had time to report regressions, giving you both timely patching and a stabilisation buffer.

Add `renovate.json` to the repo root:

```json
{
  "packageRules": [{
    "matchManagers": ["npm"],
    "minimumReleaseAge": "14 days"
  }]
}
```

To activate: install the app at [github.com/apps/renovate](https://github.com/apps/renovate) on your GitHub org/repo. It reads `renovate.json` on its own schedule from that point on.

### Before opening a browser tab to review dependency changes

When a dev server runs inside the container, VS Code automatically forwards its port to `localhost` on the host — this is how dev containers work and there is no way to prevent it. Any browser tab on your host, and any local process, can reach that forwarded port. If an agent has injected malicious code into the page, opening it in your main browser profile exposes all cookies, `localStorage`, and credentials stored there to that page. A malicious page can also make `fetch()` calls to other `localhost` ports (e.g., to the MarkLogic admin UI or any other service bound to loopback), because all `localhost` ports share the same origin from the browser's perspective — there is no cross-origin block between them.

Two mitigations used together reduce this risk:

**1. Inspect what changed before loading the page:**

```bash
git diff HEAD pnpm-lock.yaml   # packages added or changed
git diff HEAD app/package.json
```

If you see unexpected new packages or version bumps you did not request, investigate before loading the page.

**2. Use a dedicated browser profile (see below).**

### Browser isolation for reviewing agent-built pages

Use Firefox with a dedicated profile for all localhost development previews:

1. Create a new Firefox profile (e.g. `Developer Preview`) — it gets its own cookie jar, `localStorage`, credentials, and extensions, completely isolated from your main profile.
2. Add the `privacy.firstparty.isolate` preference to that profile.
3. Open all agent-built `localhost` pages in this profile only — never your main profile.

This profile's isolation means a malicious page at `localhost:4200` cannot harvest cookies or credentials from your main browser profile, because they reside in a separate sandbox. It does not prevent `fetch()` calls to other localhost ports, but it eliminates the credential-harvest angle.

## Opening the Dev Container

```
Cmd+Shift+P → Dev Containers: Reopen in Container
```

VS Code rebuilds or reuses the container image, then reopens the workspace at `/workspace`. A green indicator in the VS Code status bar confirms you are inside the container. Every terminal, task, and agent tool call runs inside the container while that indicator is present.

```
Cmd+Shift+P → Dev Containers: Reopen Folder Locally
```

Returns to the host. Run `docker compose` commands from the host, not from inside the container.

## Base Image and Tools

| Item | Value |
|---|---|
| Base image | `mcr.microsoft.com/devcontainers/base:ubuntu-22.04` (fixed — not configurable per project) |
| Java | Installed via `apt-get` in the Dockerfile (version set by `dockerfileBuild.toolchains.java.version` in the answers file) |
| Node.js | Installed via NodeSource's apt repo in the Dockerfile — GPG key saved to a keyring, never piped into a shell (version set by `dockerfileBuild.toolchains.node.version`) |
| Package manager | pnpm, if the project opts into it (see `dockerfileBuild.toolchains.pnpm.npmrcPath` in the answers file) |
| User | `vscode` (UID 1000, non-root) by default — overridable via `remoteUser` |

Devcontainer Features are intentionally not used for Node/Java: the Java feature installs via SDKMAN, which fetches from `adoptium.net` at container-creation time — an unpinned, runtime network dependency. Installing via `apt-get`/NodeSource in the Dockerfile moves that fetch to build time, from vetted, signed sources. See [`lib/toolchains.sh`](lib/toolchains.sh) for the exact recipes.

## Mount Layout

The workspace is mounted read-write. Sub-directories are overlaid read-only — an agent can read them but write attempts fail with `EROFS`.

| Host path | Container path | Writable |
|---|---|---|
| `./` | `/workspace` | Yes |
| `./data/` | `/workspace/data` | No |

`/var/run/docker.sock` is intentionally **not** mounted. The container cannot control Docker on the host. Manage `docker compose` from the host terminal.

## Security Hardening

The container drops all Linux capabilities and re-adds only what build tools actually need:

| Capability | Why retained |
|---|---|
| `CHOWN` | npm/mvn/gradle adjust file ownership during installs |
| `SETUID` / `SETGID` | Process user-switching used by some JVM operations |
| `DAC_OVERRIDE` | Read/write build outputs regardless of permission bits |
| `FOWNER` | Operations on files owned by other UIDs |

Additional hardening applied via `runArgs`:
- `--security-opt no-new-privileges` — blocks privilege escalation via setuid binaries
- `--cap-drop ALL` — starts with zero capabilities
- Root account locked (`passwd -l root` in `postCreateCommand`)
- `vscode` user removed from `sudo` group

## npm Registry Block

Public npm registries are blocked via `--add-host` entries that null-route the hostnames (`0.0.0.0` for IPv4, `::1` for IPv6). The hostname list comes from `blockedRegistryHostsFile` (a plain newline-delimited file, e.g. [`external/dev-container-config/examples/blockedRegistryHosts.txt`](examples/blockedRegistryHosts.txt)) merged with any ad-hoc `blockedRegistryHosts` entries in the answers file -- the generator expands each one into both the IPv4 and IPv6 form automatically. No list is hardcoded in the generator itself.

This is a hand-curated list of known public npm mirrors, not an official or universal standard -- trim it, extend it, or swap in your own file per project depending on which private registry you use and which mirrors are realistic bypass routes for your threat model. It's also a DNS-level blocklist, not a network firewall: it only stops resolution of *these specific hostnames*; it does not block outbound connections to a raw IP address or to a mirror not on the list. Treat it as defense-in-depth alongside `npm-guard.sh`, not as a complete egress block.

Use `pnpm` with the internal registry instead, for example:

```bash
pnpm install --registry https://pkg.harness.io/pkg/<hash>/<org>/npm/
```

Registry blocking does **not** require pnpm: npm can use an internal registry
too. Enabling the pnpm toolchain is a separate decision to require pnpm and
install its npm guard. Projects without this toolchain retain their existing
Node installation behavior; the generator does not configure package policy
for those projects.

Set `dockerfileBuild.toolchains.pnpm.npmrcPath` to a corporate/project-supplied
`.npmrc`. That file is the policy source; do not repeat its policy in answers.
The supported translation is:

| Corporate `.npmrc` entry | Generated pnpm 12 user configuration |
|---|---|
| `registry=` and scoped registry/auth entries | Read from the user's `.npmrc` |
| `min-release-age=14` | `minimumReleaseAge: 20160` (minutes) |
| `ignore-scripts=true` | `ignoreScripts: true` |
| `strict-ssl=true` | `strictSsl: true` |
| `verify-deps-before-run=never` | `verifyDepsBeforeRun: false` |

`registry=` is required. Age must be a non-negative integer in days; absent
age means 0, and absent `ignore-scripts` means false, matching npm's default.
Boolean policy values must be `true` or `false`. Entries use unquoted
`key=value` syntax; blank lines, full-line `#`/`;` comments, whitespace around
assignments and CRLF are supported. Duplicate keys use the last value.
Unknown npm entries are preserved, not implicitly translated. pnpm-only
`verify-deps-before-run` is removed from the generated `.npmrc` after
translation; supported values also include booleans, `install`, `warn`,
`error`, and `prompt`. Invalid supported policy values fail generation.

Modern npm supports `min-release-age` in days; the old npm bundled with a Node
distribution may not. pnpm 12 uses a different setting and YAML configuration:
it does not enforce npm's age or script settings merely because they appear
in `.npmrc`.

The generated build:

1. Configures root's `.npmrc` and `.config/pnpm/config.yaml`.
2. Uses the bundled npm only to install an explicitly selected, age-eligible
   npm release. The new npm then enforces age policy for pnpm's bootstrap
   dependencies too.
3. Installs supported pnpm 12 and validates that its configuration loads.
4. Copies registry and translated policy to the configured non-root user's
   home, resolving that home from the image's account database.
5. Provides writable `/opt/devcontainer/pnpm` and `/opt/devcontainer/bin`
   directories and adds the latter to the image's PATH, including outside VS
   Code terminals.

pnpm is configured with strict release-age checks and no exemption for
missing publication timestamps. A registry rejection or no eligible version
fails explicitly; there is no fallback to the public registry or a relaxed
policy. Age filtering does not replace vulnerability scanning or corporate
approval. pnpm bootstrap alone permits pnpm's own installation scripts to
link its platform executable; it does not enable runtime package scripts.

### Version selection and updates

Consumers can select versions without changing this repository:

```json
"pnpm": {
  "npmrcPath": "../.npmrc",
  "npmVersion": "11",
  "version": "12"
}
```

The defaults select the newest eligible stable npm 11 and pnpm 12 releases.
This is **rolling selection**, not a reproducible pin. Exact selections such
as `"npmVersion": "11.21.0"` and `"version": "12.12.0"` are also accepted and
must satisfy the age policy. npm must be at least 11.10.0. The build checks
each selected package manager's Node engine requirement and fails with an
actionable error on incompatibility. pnpm majors other than 12 require
configuration support and testing in this repository before use.

Successful selections are recorded in
`/usr/local/share/devcontainer/package-managers.json`. For repeatable builds,
review these versions and enter exact selections in the answers file.
Regularly refresh and test those selections; do not pin indefinitely. Use
committed lockfiles and frozen-lockfile installs for application dependencies.
An exact top-level global CLI version alone does not lock its transitive
dependencies. No automatic update scheduler, vulnerability scanner, or
global CLI lockfile is provided.

This policy applies to npm-registry packages, not base images, apt packages,
or NodeSource's Node distributions. Runtime hostname blocking is not applied
to Docker build networking.

### Runtime installs and project configuration

With the generated user defaults, a consumer may set:

```json
"postCreateCommand": "pnpm add --global cline"
```

Global installs use the configured registry and policy even outside the
workspace. For a project dependency instead, use `pnpm add cline` and invoke
it with `pnpm exec cline`.

An application in `ui/` can keep its own `.npmrc` for its registry. pnpm
behavior belongs in its applicable `pnpm-workspace.yaml`; the generator
neither rewrites application files nor translates every nested `.npmrc`.
Project/CLI settings can override user defaults, so these defaults are not
an immutable security boundary. Server-side registry policy remains
important.

Literal authentication tokens/passwords are rejected before copying into
the generated build context. Environment placeholders such as `${NPM_TOKEN}`
are permitted, but the generator does not deliver secrets: authenticated
builds require appropriate BuildKit secrets and runtime credentials supplied
separately. Do not replace placeholders with secrets in generated files.

- `templates/npm-guard.sh` is COPY'd into the image at `/etc/profile.d/npm-guard.sh` and also into `.devcontainer/npm-guard.sh` in the build context. It intercepts `npm install`, `npm ci`, `npm i`, and `npm add` shell-wide and redirects you to `pnpm`:

  ```
  [BLOCKED] This project uses pnpm. Run: pnpm install
  ```

- `postCreateCommand` registers `/etc/profile.d/npm-guard.sh` in `~/.bashrc` (VS Code terminals are non-login shells). Registration is grouped before any consumer command so an existing entry does not skip that command. It does not depend on the workspace's path or the generator's output directory.

### Migrating existing generated containers

Keep the corporate `.npmrc` as the source. Re-run the updated generator and
**rebuild** the container; reconnecting to the existing container will not
install the new user configuration. Replace `npm install -g cline` with
`pnpm add --global cline` in the consumer's answers, not the generated JSON.
Do not remove the registry blocks or use `command npm` to bypass the guard.

The project's real `.npmrc` is never committed to this generator repo.

### How file paths in the answers file are resolved

`dockerfileBuild.toolchains.pnpm.npmrcPath`, `blockedRegistryHostsFile`, and `dockerfileBuild.files[].sourcePath` all use the same rules. Paths are resolved relative to **the directory containing the answers file**, not the directory you run `generate.sh` from:

| Path form | Resolved against | Typical use |
|---|---|---|
| `./foo` or `../foo` | The answers file's directory | Files your project supplies (e.g. `.npmrc`) |
| `foo/bar` (no leading `./` or `../`) | The submodule root (`external/dev-container-config/`) | Built-in files (e.g. `examples/blockedRegistryHosts.txt`, `templates/npm-guard.sh`) |
| `/abs/path` | Used as-is | Not recommended -- not portable across machines |

Because of this, `../` is only correct if the answers file lives one level below the files it references. For example, with the answers file at `.devcontainer/devcontainer.answers.json` and the project's `.npmrc` at the project root:

```json
"dockerfileBuild": { "toolchains": { "pnpm": { "npmrcPath": "../.npmrc" } } },
"blockedRegistryHostsFile": "examples/blockedRegistryHosts.txt"
```

If the answers file is at the project root instead, use `./.npmrc`. To reference a hosts file kept in your own project rather than the submodule, use `./` or `../` (e.g. `../blocked-hosts.txt`). A path like `../external/dev-container-config/examples/...` only works when the answers file is in `.devcontainer/` (as saved by interactive mode); from a project-root answers file it points outside the project and fails with `blockedRegistryHostsFile not found`. Prefer the prefix-free `examples/...` form for built-in files, which works from any location.

When you use interactive mode, absolute paths you enter are saved to `devcontainer.answers.json` as paths relative to `.devcontainer/` so the file stays portable.

`dockerfileBuild.toolchains.pnpm` requires `dockerfileBuild.toolchains.node` to also be set; `generate.sh` fails fast with a clear error otherwise.

## Reaching Host Services

`host.docker.internal` resolves to the host machine from inside the container. The `--add-host host.docker.internal:host-gateway` entry in `runArgs` ensures this works on Linux as well as Docker Desktop for Mac.

## Files

Generated into a consuming project's `.devcontainer/` by `generate.sh` (see [Layout of this repo](#layout-of-this-repo) above for the generator's own files):

| File | Purpose |
|---|---|
| `.devcontainer/devcontainer.json` | Container definition: image, mounts, runArgs, features, postCreateCommand. Generated — do not hand-edit |
| `.devcontainer/Dockerfile` | Toolchain installs + root-lockdown, built from the answers file. Generated — do not hand-edit |
| `.devcontainer/npm-guard.sh` | Copied from `templates/npm-guard.sh` when `dockerfileBuild.toolchains.pnpm` is set (or via `dockerfileBuild.files[]`) |
| `.devcontainer/install-pnpm.sh` | Copied from `templates/install-pnpm.sh` when `dockerfileBuild.toolchains.pnpm` is set |
| `.devcontainer/install-package-manager.cjs` | Shared age-aware npm/pnpm bootstrap implementation |
| `.devcontainer/pnpm-config.yaml` | Translated corporate policy and global CLI locations, configured for root and the runtime user |
| `.devcontainer/.npmrc` | Derived from `dockerfileBuild.toolchains.pnpm.npmrcPath`, with translated pnpm-only behavior removed -- project-specific |
| `.devcontainer/devcontainer.answers.json` | The project's answers file — the real source of truth. Saved automatically by `generate.sh` (from `--answers <file>` or interactive prompts); re-run `generate.sh --answers .devcontainer/devcontainer.answers.json` after editing it |

## Updating

Pull upstream changes into a consuming project, from the consumer's repo root:

```bash
git submodule update --remote external/dev-container-config   # fetches + fast-forwards to the submodule's remote HEAD
git add external/dev-container-config                          # stage the new commit pointer
git commit -m "chore: update dev-container-config"           # the pointer bump is a real commit in the consumer repo
```

`--remote` is the key flag — a plain `git submodule update` alone re-checks-out whatever commit the consumer repo currently *points at*; it won't move that pointer forward on its own. Equivalently, from inside the submodule itself: `cd external/dev-container-config && git pull && cd - && git add external/dev-container-config && git commit`.

Re-run the generator afterward to pick up changes (new toolchain recipes, hardening tweaks, etc.):

```bash
./external/dev-container-config/generate.sh --answers .devcontainer/devcontainer.answers.json
```

This won't clobber hand-edits — see [Generating a devcontainer for your project](#generating-a-devcontainer-for-your-project) for the hash-conflict/`.new` behavior.

## Troubleshooting

| Symptom | Check |
|---|---|
| `host.docker.internal` not resolving | Ensure `--add-host host.docker.internal:host-gateway` is in `runArgs` |
| `npm install` blocked | Intentional — use `pnpm install` with the Harness registry |
| Global install contacts registry.npmjs.org | Regenerate and rebuild to install runtime user registry configuration; do not unblock the public registry |
| Harness returns 403 for a recent dependency | Check effective pnpm `minimumReleaseAge`; npm 10 does not enforce `min-release-age`. Other Harness policy blocks still require investigation |
| Cannot reach MarkLogic | Confirm `docker compose up -d` is running on the **host**, not inside the container |
| pnpm not found after rebuild | `postCreateCommand` may have failed; check the creation log in the VS Code output panel |
| Write to `data/` or `licence/` fails | Those mounts are read-only by design (`EROFS`) |
| `generate.sh` wrote a `.new` file | The existing `devcontainer.json`/`Dockerfile` was hand-edited since it was last generated — diff and merge manually, then delete the `.new` file |
| Need to regenerate anyway | `./generate.sh --answers <file> --force` overwrites regardless of hand-edits |
