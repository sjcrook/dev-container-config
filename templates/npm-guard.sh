# npm-guard.sh
# Intercepts npm install / i / ci / add and redirects to pnpm.
# Sourced by ~/.bashrc (interactive sessions) and /etc/profile.d/ (login shells).
# The shebang is intentionally absent — this file is sourced, not executed.

if [ -n "${BASH_VERSION}" ]; then
    npm() {
        case "$1" in
            install|i|ci|add)
                echo "[BLOCKED] This project uses pnpm. Run: pnpm install" >&2
                return 1
                ;;
            *)
                command npm "$@"
                ;;
        esac
    }
    export -f npm
fi
