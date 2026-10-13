#!/usr/bin/env bash
# Built-in, security-reviewed install recipes for common toolchains.
# Centralizing these means consumers reference a version number instead of
# hand-rolling apt/curl steps per project (where supply-chain mistakes creep in).
set -euo pipefail

toolchain_node_dockerfile() {
  local version="$1"
  cat <<EOF

# -- Node.js (NodeSource apt repo; GPG key saved to a keyring, never piped to a
#    shell -- apt verifies package signatures against it at install time) ------
RUN set -eux; \\
    apt-get update; \\
    apt-get install -y ca-certificates curl gnupg; \\
    mkdir -p /etc/apt/keyrings; \\
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.asc; \\
    chmod a+r /etc/apt/keyrings/nodesource.asc; \\
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.asc] https://deb.nodesource.com/node_${version}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list; \\
    apt-get update; \\
    apt-get install -y nodejs
EOF
}

toolchain_java_dockerfile() {
  local version="$1"
  cat <<EOF

# -- Java (Ubuntu apt repository; GPG-signed, build-time only) -----------------
RUN apt-get update \\
    && apt-get install -y openjdk-${version}-jdk-headless
# ENV does not expand shell commands, so create an arch-independent symlink.
RUN ln -s /usr/lib/jvm/java-${version}-openjdk-\$(dpkg --print-architecture) /usr/lib/jvm/java-${version}-openjdk
ENV JAVA_HOME=/usr/lib/jvm/java-${version}-openjdk
EOF
}

toolchain_pnpm_dockerfile() {
  cat <<'EOF'

# -- pnpm (pinned via install-pnpm.sh, which reads the registry and
#    min-release-age policy from the project's own .npmrc -- nothing
#    registry-specific is hardcoded in this submodule) -------------------------
# .npmrc is copied first so install-pnpm.sh can read it when it runs.
# corepack disable is intentionally omitted here: Node comes from NodeSource's
# apt repo (not the javascript-node devcontainer feature/image), so there is
# no pre-existing Corepack pnpm shim to conflict with.
COPY .npmrc /root/.npmrc
COPY install-pnpm.sh /usr/local/bin/install-pnpm.sh
RUN chmod +x /usr/local/bin/install-pnpm.sh \
    && /usr/local/bin/install-pnpm.sh

# -- npm-guard.sh: blocks npm install/ci/i/add shell-wide, redirects to pnpm --
COPY npm-guard.sh /etc/profile.d/npm-guard.sh
RUN chmod +x /etc/profile.d/npm-guard.sh
EOF
}
