# Dev Container

A VSCode Dev Container designed to create a secure, isolated environment in which to run automomous agents. It does **not** run the `docker compose` stack — the stack runs on the host. Running the stack inside the container would require mounting `/var/run/docker.sock`, which would give any process in the container — including an autonomous agent — full control over Docker on the host machine. Instead, the container connects to host services via `host.docker.internal`.

This repo is meant to be vendored into other projects (e.g. as a git submodule). It does not ship a single fixed `devcontainer.json`/`Dockerfile` — it ships a **generator** that produces those files from a project-specific answers file, so every consuming project gets the same security hardening with only its real differences (toolchain versions, extra files, extra hosts, etc.) varying.

Everything in this repo is the vendored, read-only core (`generate.sh`, `lib/`, `schema/`, `examples/`, `templates/`). The only files that land in a consuming project are whatever `generate.sh` writes into `--out-dir` (default `.devcontainer/`), plus the project's own answers file that you author yourself.

## Install

Vendor this repo as a git submodule in the consuming project:

```bash
git submodule add <this-repo-url> vendor/dev-container-config
git submodule update --init --recursive
```

Unlike some vendored tools, nothing here hardcodes that path — `generate.sh` resolves its own location at runtime via `BASH_SOURCE`, so you can vendor it anywhere. `vendor/dev-container-config` is just the convention used throughout this README and in the shipped examples.

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
./vendor/dev-container-config/generate.sh --answers .devcontainer/devcontainer.answers.json

# Interactive: answer a handful of prompts; produces the same shape under the hood
./vendor/dev-container-config/generate.sh

# Write somewhere other than ./.devcontainer, or force-overwrite hand-edited output
./vendor/dev-container-config/generate.sh --answers .devcontainer/devcontainer.answers.json --out-dir .devcontainer --force
```

Both modes write `devcontainer.json` and `Dockerfile` into `--out-dir` (default `.devcontainer/`). Start from [`vendor/dev-container-config/examples/minimal.answers.json`](examples/minimal.answers.json) or [`vendor/dev-container-config/examples/full.answers.json`](examples/full.answers.json) and see [`vendor/dev-container-config/schema/answers.schema.json`](schema/answers.schema.json) for every field.

**Generated files are not meant to be hand-edited.** Each one carries a header comment with a content hash. Re-running `generate.sh`:
- Silently overwrites the file if it still matches that hash (untouched since the last generation).
- If the file was hand-edited, leaves it alone and writes the new output to `devcontainer.json.new` / `Dockerfile.new` instead, so you can merge manually. `--force` skips this check and always overwrites.

If something a project needs isn't expressible in the answers file, that's a signal to add a field to the schema — not to hand-edit the generated output.

### Layout of this repo

| Path | Purpose |
|---|---|
| `generate.sh` | Entry point — parses args, loads/collects answers, renders output |
| `lib/` | Generator implementation (bash + `jq`) — toolchain recipes, renderers, hash/conflict handling, file copying |
| `schema/answers.schema.json` | Documents every answers-file field |
| `examples/*.answers.json` | Starting points to copy into a consuming project |
| `templates/npm-guard.sh` | Built-in file consuming projects can reference via `files[]` |

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
| Java | Installed via `apt-get` in the Dockerfile (version set by `toolchains.java.version` in the answers file) |
| Node.js | Installed via NodeSource's apt repo in the Dockerfile — GPG key saved to a keyring, never piped into a shell (version set by `toolchains.node.version`) |
| Package manager | pnpm, if the project opts into it (see `postCreateCommand` / `files` in the answers file) |
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

Public npm registries are blocked via `--add-host` entries that null-route the hostnames (`0.0.0.0` for IPv4, `::1` for IPv6). The hostname list comes from `blockedRegistryHostsFile` (a plain newline-delimited file, e.g. [`vendor/dev-container-config/examples/blockedRegistryHosts.txt`](examples/blockedRegistryHosts.txt)) merged with any ad-hoc `blockedRegistryHosts` entries in the answers file -- the generator expands each one into both the IPv4 and IPv6 form automatically. No list is hardcoded in the generator itself.

This is a hand-curated list of known public npm mirrors, not an official or universal standard -- trim it, extend it, or swap in your own file per project depending on which private registry you use and which mirrors are realistic bypass routes for your threat model. It's also a DNS-level blocklist, not a network firewall: it only stops resolution of *these specific hostnames*; it does not block outbound connections to a raw IP address or to a mirror not on the list. Treat it as defense-in-depth alongside `npm-guard.sh`, not as a complete egress block.

Use `pnpm` with the internal registry instead, for example:

```bash
pnpm install --registry https://pkg.harness.io/pkg/<hash>/<org>/npm/
```

The `npm-guard.sh` script intercepts `npm install`, `npm ci`, `npm i`, and `npm add` shell-wide and redirects you to `pnpm`:

```
[BLOCKED] This project uses pnpm. Run: pnpm install
```

The guard is sourced in `~/.bashrc` (user sessions) and installed to `/etc/profile.d/npm-guard.sh` (all sessions) by `postCreateCommand`.

## Reaching Host Services

`host.docker.internal` resolves to the host machine from inside the container. The `--add-host host.docker.internal:host-gateway` entry in `runArgs` ensures this works on Linux as well as Docker Desktop for Mac.

## Files

Generated into a consuming project's `.devcontainer/` by `generate.sh` (see [Layout of this repo](#layout-of-this-repo) above for the generator's own files):

| File | Purpose |
|---|---|
| `.devcontainer/devcontainer.json` | Container definition: image, mounts, runArgs, features, postCreateCommand. Generated — do not hand-edit |
| `.devcontainer/Dockerfile` | Toolchain installs + root-lockdown, built from the answers file. Generated — do not hand-edit |
| `.devcontainer/npm-guard.sh` | Copied from `templates/npm-guard.sh` if the answers file's `files[]` references it |
| `.devcontainer/devcontainer.answers.json` | The project's own answers file — the real source of truth; re-run `generate.sh` after editing it |

## Updating

Pull upstream changes into a consuming project, from the consumer's repo root:

```bash
git submodule update --remote vendor/dev-container-config   # fetches + fast-forwards to the submodule's remote HEAD
git add vendor/dev-container-config                          # stage the new commit pointer
git commit -m "chore: update dev-container-config"           # the pointer bump is a real commit in the consumer repo
```

`--remote` is the key flag — a plain `git submodule update` alone re-checks-out whatever commit the consumer repo currently *points at*; it won't move that pointer forward on its own. Equivalently, from inside the submodule itself: `cd vendor/dev-container-config && git pull && cd - && git add vendor/dev-container-config && git commit`.

Re-run the generator afterward to pick up changes (new toolchain recipes, hardening tweaks, etc.):

```bash
./vendor/dev-container-config/generate.sh --answers .devcontainer/devcontainer.answers.json
```

This won't clobber hand-edits — see [Generating a devcontainer for your project](#generating-a-devcontainer-for-your-project) for the hash-conflict/`.new` behavior.

## Troubleshooting

| Symptom | Check |
|---|---|
| `host.docker.internal` not resolving | Ensure `--add-host host.docker.internal:host-gateway` is in `runArgs` |
| `npm install` blocked | Intentional — use `pnpm install` with the Harness registry |
| Cannot reach MarkLogic | Confirm `docker compose up -d` is running on the **host**, not inside the container |
| pnpm not found after rebuild | `postCreateCommand` may have failed; check the creation log in the VS Code output panel |
| Write to `data/` or `licence/` fails | Those mounts are read-only by design (`EROFS`) |
| `generate.sh` wrote a `.new` file | The existing `devcontainer.json`/`Dockerfile` was hand-edited since it was last generated — diff and merge manually, then delete the `.new` file |
| Need to regenerate anyway | `./generate.sh --answers <file> --force` overwrites regardless of hand-edits |
