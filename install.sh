#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Airflow Variable Extractor — Remote Runner
# Usage: curl -fsSL https://your-host.com/install.sh | bash -s -- --mode api --url http://localhost:8080
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_URL="${GET_AIRFLOW_VARS_URL:-https://raw.githubusercontent.com/MushroomSquad/airparse/main/get_airflow_vars.py}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Check / Install uv ───────────────────────────────────────────────────────
ensure_uv() {
    if command -v uv &>/dev/null; then
        info "uv found: $(uv --version)"
        return
    fi

    warn "uv not found. Installing..."
    if command -v curl &>/dev/null; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
    elif command -v wget &>/dev/null; then
        wget -qO- https://astral.sh/uv/install.sh | sh
    else
        error "Neither curl nor wget found. Install uv manually: https://docs.astral.sh/uv/"
    fi

    # Add to PATH for current session
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    if ! command -v uv &>/dev/null; then
        error "uv installation failed. Please install manually."
    fi
    info "uv installed: $(uv --version)"
}

# ── Download and run script ──────────────────────────────────────────────────
main() {
    ensure_uv

    TMPDIR="${TMPDIR:-/tmp}"
    SCRIPT_PATH="$TMPDIR/get_airflow_vars_$$.py"

    info "Downloading script from $SCRIPT_URL"
    if command -v curl &>/dev/null; then
        curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
    else
        wget -qO "$SCRIPT_PATH" "$SCRIPT_URL"
    fi

    trap 'rm -f "$SCRIPT_PATH"' EXIT

    info "Running with args: $*"
    uv run "$SCRIPT_PATH" "$@"
}

main "$@"

main "$@"
