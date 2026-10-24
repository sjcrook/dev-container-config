#!/usr/bin/env bash
set -euo pipefail

POLICY_FILE="${POLICY_FILE:-/root/.config/pnpm/config.yaml}"
NPM_VERSION="${NPM_VERSION:-11}"
PNPM_VERSION="${PNPM_VERSION:-12}"
INSTALLER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-package-manager.cjs"

node "${INSTALLER}" npm "${NPM_VERSION}" "${POLICY_FILE}"
node "${INSTALLER}" pnpm "${PNPM_VERSION}" "${POLICY_FILE}"
npm --version
pnpm --version
