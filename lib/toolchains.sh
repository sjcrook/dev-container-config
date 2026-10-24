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
  local remote_user="$1" npm_version="$2" pnpm_version="$3"
  cat <<EOF

# -- npm/pnpm: corporate registry and translated policy ----------------------
COPY .npmrc /root/.npmrc
COPY pnpm-config.yaml /root/.config/pnpm/config.yaml
COPY install-package-manager.cjs /usr/local/bin/install-package-manager.cjs
COPY install-pnpm.sh /usr/local/bin/install-pnpm.sh
RUN NPM_VERSION=${npm_version} PNPM_VERSION=${pnpm_version} bash /usr/local/bin/install-pnpm.sh

# Configure the runtime user as well as root. Global CLIs must also work when
# lifecycle commands run outside the mounted workspace.
RUN set -eux; \\
    home="\$(getent passwd ${remote_user} | cut -d: -f6)"; \\
    test -n "\$home"; \\
    mkdir -p "\$home/.config/pnpm" /opt/devcontainer/bin /opt/devcontainer/pnpm; \\
    cp /root/.npmrc "\$home/.npmrc"; \\
    cp /root/.config/pnpm/config.yaml "\$home/.config/pnpm/config.yaml"; \\
    chown ${remote_user} "\$home/.npmrc"; \\
    chown -R ${remote_user} "\$home/.config/pnpm" /opt/devcontainer
ENV PATH="/opt/devcontainer/bin:\${PATH}"

# -- npm-guard.sh: blocks npm install/ci/i/add shell-wide, redirects to pnpm --
COPY npm-guard.sh /etc/profile.d/npm-guard.sh
RUN chmod +x /etc/profile.d/npm-guard.sh
EOF
}
