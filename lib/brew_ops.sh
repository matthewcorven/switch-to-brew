#!/bin/bash
# switch-to-brew — Homebrew adoption operations
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

# ── Switch a single app to Homebrew management ──────────────────────────────
# Uses `brew install --cask --adopt` which links the existing .app bundle
# into Homebrew's tracking without reinstalling.
#
# Args: cask_token  app_name  app_path  [dry_run]
# Returns: 0 on success, 1 on failure

stb_brew_adopt() {
    local cask_token="$1"
    local app_name="$2"
    local app_path="$3"
    local dry_run="${4:-false}"

    if [ "$dry_run" = "true" ]; then
        printf '  %s[dry-run]%s Would run: brew install --cask %s --adopt\n' \
            "${C_YELLOW}" "${C_RESET}" "$cask_token" >&2
        return 0
    fi

    stb_info "Adopting ${C_BOLD}${app_name}${C_RESET} via cask ${C_GREEN}${cask_token}${C_RESET}..."

    local output exit_code
    output="$(brew install --cask "$cask_token" --adopt 2>&1)" && exit_code=0 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        stb_success "${app_name} is now managed by Homebrew (${cask_token})"
        return 0
    else
        # Check if it's already installed
        if echo "$output" | grep -q "already installed"; then
            stb_success "${app_name} is already managed by Homebrew (${cask_token})"
            return 0
        fi
        stb_error "Failed to adopt ${app_name}:"
        echo "$output" | sed 's/^/    /' >&2
        return 1
    fi
}

# ── Batch switch ─────────────────────────────────────────────────────────────
# Input on stdin: TSV lines (app_name \t cask_token \t app_path \t source \t bundle_id)
# Args: [--dry-run]

stb_brew_adopt_batch() {
    local dry_run="false"
    [ "${1:-}" = "--dry-run" ] && dry_run="true"

    # Ensure cache dir exists for temp file
    mkdir -p "$STB_CACHE_DIR"

    # Read into temp file
    local batch_file="${STB_CACHE_DIR}/_adopt_batch"
    cat > "$batch_file"

    local total
    total="$(grep -c . "$batch_file" || true)"
    local succeeded=0 failed=0 skipped=0

    echo "" >&2
    if [ "$dry_run" = "true" ]; then
        stb_info "Dry-run mode: showing what would happen for ${total} $(stb_plural "$total" app)..."
    else
        stb_info "Switching ${total} $(stb_plural "$total" app) to Homebrew management..."
    fi
    echo "" >&2

    while IFS="$(printf '\t')" read -r app_name cask_token app_path source bundle_id; do
        [ -z "$app_name" ] && continue

        if [ "$source" = "app-store" ]; then
            stb_warn "Skipping ${app_name} (App Store app — must be uninstalled from App Store first)"
            skipped=$((skipped + 1))
            continue
        fi

        if stb_brew_adopt "$cask_token" "$app_name" "$app_path" "$dry_run"; then
            succeeded=$((succeeded + 1))
        else
            failed=$((failed + 1))
        fi
    done < "$batch_file"

    rm -f "$batch_file"

    # Summary
    echo "" >&2
    printf '%s%s── Summary ─────────────────────────────────────%s\n' "${C_BOLD}" "${C_WHITE}" "${C_RESET}" >&2
    [ "$succeeded" -gt 0 ] && stb_success "${succeeded} $(stb_plural "$succeeded" app) switched to Homebrew"
    [ "$skipped" -gt 0 ]   && stb_warn "${skipped} $(stb_plural "$skipped" app) skipped"
    [ "$failed" -gt 0 ]    && stb_error "${failed} $(stb_plural "$failed" app) failed"

    [ "$failed" -gt 0 ] && return 1
    return 0
}
