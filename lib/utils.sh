#!/bin/bash
# switch-to-brew — shared utility functions
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

# ── Logging ──────────────────────────────────────────────────────────────────

stb_info() {
    printf '%s%s▸%s %s\n' "${C_BLUE}" "${C_BOLD}" "${C_RESET}" "$*" >&2
}

stb_success() {
    printf '%s%s✔%s %s\n' "${C_GREEN}" "${C_BOLD}" "${C_RESET}" "$*" >&2
}

stb_warn() {
    printf '%s%s⚠%s %s\n' "${C_YELLOW}" "${C_BOLD}" "${C_RESET}" "$*" >&2
}

stb_error() {
    printf '%s%s✘%s %s\n' "${C_RED}" "${C_BOLD}" "${C_RESET}" "$*" >&2
}

stb_debug() {
    [ -n "${STB_DEBUG:-}" ] && printf '%s[debug]%s %s\n' "${C_DIM}" "${C_RESET}" "$*" >&2
}

# ── Spinner for long operations ──────────────────────────────────────────────

stb_spinner_start() {
    local msg="${1:-Working...}"
    if [ -t 2 ]; then
        printf '%s %s' "${C_DIM}⠋${C_RESET}" "$msg" >&2
        (
            while true; do
                for frame in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
                    printf '\r%s%s%s %s' "${C_CYAN}" "$frame" "${C_RESET}" "$msg" >&2
                    sleep 0.1
                done
            done
        ) &
        STB_SPINNER_PID=$!
        disown "$STB_SPINNER_PID" 2>/dev/null
    fi
}

stb_spinner_stop() {
    if [ -n "${STB_SPINNER_PID:-}" ]; then
        kill "$STB_SPINNER_PID" 2>/dev/null
        wait "$STB_SPINNER_PID" 2>/dev/null
        unset STB_SPINNER_PID
        printf '\r\033[K' >&2
    fi
}

# ── Dependency checks ────────────────────────────────────────────────────────

stb_require_brew() {
    if ! command -v brew >/dev/null 2>&1; then
        stb_error "Homebrew is not installed."
        stb_error "Install it from https://brew.sh"
        exit "$EXIT_NO_BREW"
    fi
}

stb_require_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        stb_error "This tool only runs on macOS."
        exit "$EXIT_ERR"
    fi
}

# ── Cache helpers ────────────────────────────────────────────────────────────

stb_cache_init() {
    mkdir -p "$STB_CACHE_DIR"
}

stb_cache_get() {
    local key="$1"
    local file="${STB_CACHE_DIR}/${key}"
    if [ -f "$file" ]; then
        local now mod_time age
        now="$(date +%s)"
        mod_time="$(stat -f '%m' "$file" 2>/dev/null || echo 0)"
        age=$(( now - mod_time ))
        if [ "$age" -lt "$STB_CACHE_TTL" ]; then
            cat "$file"
            return 0
        fi
    fi
    return 1
}

stb_cache_set() {
    local key="$1"
    cat > "${STB_CACHE_DIR}/${key}"
}

stb_cache_clear() {
    rm -rf "$STB_CACHE_DIR"
    stb_success "Cache cleared."
}

# ── Misc ─────────────────────────────────────────────────────────────────────

stb_plural() {
    local count="$1" singular="$2" plural="${3:-${2}s}"
    if [ "$count" -eq 1 ]; then
        echo "$singular"
    else
        echo "$plural"
    fi
}

stb_confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    local hint="[y/N]"
    [ "$default" = "y" ] && hint="[Y/n]"

    printf '%s%s %s%s ' "${C_BOLD}" "$prompt" "${C_DIM}" "$hint" >&2
    printf '%s' "${C_RESET}" >&2
    local reply
    read -r reply
    reply="${reply:-$default}"
    case "$reply" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

stb_is_app_store_app() {
    local app_path="$1"
    local receipt="${app_path}/Contents/_MASReceipt/receipt"
    [ -f "$receipt" ]
}
