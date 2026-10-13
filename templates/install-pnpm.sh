#!/usr/bin/env bash
# install-pnpm.sh
#
# Reads the registry and min-release-age policy out of the .npmrc that was
# COPY'd alongside this script (not hardcoded here, so this file stays
# identical across every project that vendors this generator), queries that
# registry for the pnpm package manifest, and installs the latest version
# that is at least that many days old.
#
# This avoids the 403 a registry with a min-release-age gate (e.g. Harness
# Artifact Registry) returns when asked for a version newer than the gate.
#
# NPMRC can be overridden via environment variable; defaults to /root/.npmrc
# (where the Dockerfile COPYs the project's .npmrc before running this).
set -euo pipefail

NPMRC="${NPMRC:-/root/.npmrc}"

REGISTRY_URL="$(sed -n 's/^registry=\(.*\)$/\1/p' "${NPMRC}" | head -n1 | sed 's:/*$::')"
MIN_AGE_DAYS="$(sed -n 's/^min-release-age=\(.*\)$/\1/p' "${NPMRC}" | head -n1)"
MIN_AGE_DAYS="${MIN_AGE_DAYS:-0}"

if [ -z "${REGISTRY_URL}" ]; then
  echo "ERROR: no 'registry=' line found in ${NPMRC}" >&2
  exit 1
fi

echo "→ Querying ${REGISTRY_URL} for pnpm versions (min-release-age=${MIN_AGE_DAYS}d)..."

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

curl -sf "${REGISTRY_URL}/pnpm" > "$TMP"

PNPM_VERSION=$(MIN_AGE_DAYS="$MIN_AGE_DAYS" node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const cutoff = Date.now() - parseInt(process.env.MIN_AGE_DAYS) * 86_400_000;

const eligible = Object.entries(data.time || {})
    .filter(([k]) => k !== 'created' && k !== 'modified')
    .filter(([, v]) => new Date(v).getTime() < cutoff)
    .sort(([, a], [, b]) => new Date(b) - new Date(a));

if (!eligible.length) {
    process.stderr.write('ERROR: no pnpm version older than ' + process.env.MIN_AGE_DAYS + ' days found in registry\n');
    process.exit(1);
}

const [ver, ts] = eligible[0];
process.stderr.write('→ Selected pnpm@' + ver + ' (published ' + ts + ')\n');
process.stdout.write(ver);
" "$TMP")

echo "→ Installing pnpm@${PNPM_VERSION}..."
npm install -g --ignore-scripts=false "pnpm@${PNPM_VERSION}"
echo "✓ pnpm $(pnpm --version) installed"
