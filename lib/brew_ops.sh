#!/bin/bash
# switch-to-brew — Homebrew adoption operations
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

# ── Switch a single app to Homebrew management ──────────────────────────────
# Uses `brew install --cask --adopt` which links the existing .app bundle
# into Homebrew's tracking without reinstalling.
#
# On version mismatch (installed version ≠ cask version), retries with
# --force unless --strict mode is active. If --upgrade is set, runs
# `brew upgrade --cask` immediately after a successful force-adopt.
#
# Args: cask_token  app_name  app_path  [dry_run]
# Globals read: STB_STRICT, STB_UPGRADE
# Returns: 0 on success, 1 on failure

stb_brew_adopt() {
    local cask_token="$1"
    local app_name="$2"
    local app_path="$3"
    local dry_run="${4:-false}"

    if [ "$dry_run" = "true" ]; then
        printf '  %s[dry-run]%s Would run: brew install --cask %s --adopt\n' \
            "${C_YELLOW}" "${C_RESET}" "$cask_token" >&2
        if [ "$STB_UPGRADE" = "true" ]; then
            printf '  %s[dry-run]%s On version mismatch, would replace with latest cask version\n' \
                "${C_YELLOW}" "${C_RESET}" >&2
        fi
        return 0
    fi

    stb_info "Adopting ${C_BOLD}${app_name}${C_RESET} via cask ${C_GREEN}${cask_token}${C_RESET}..."

    local output exit_code
    output="$(brew install --cask "$cask_token" --adopt 2>&1)" && exit_code=0 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        stb_success "${app_name} is now managed by Homebrew (${cask_token})"
        _stb_maybe_upgrade "$cask_token" "$app_name"
        return 0
    fi

    # Check if it's already installed
    if echo "$output" | grep -q "already installed"; then
        stb_success "${app_name} is already managed by Homebrew (${cask_token})"
        _stb_maybe_upgrade "$cask_token" "$app_name"
        return 0
    fi

    # Detect version mismatch
    if echo "$output" | grep -q "short version of"; then
        local installed_ver cask_ver
        installed_ver="$(echo "$output" | grep "short version of" | sed 's/.*is \([^ ]*\) for .*/\1/' | head -1)"
        cask_ver="$(echo "$output" | grep "short version of" | sed 's/.*is \([^ ]*\) but.*/\1/' | head -1)"

        if [ "$STB_STRICT" = "true" ]; then
            stb_error "Version mismatch for ${app_name}: installed=${installed_ver}, cask=${cask_ver}"
            stb_error "Use without --strict to force-adopt and let 'brew upgrade' update later."
            echo "$output" | sed 's/^/    /' >&2
            return 1
        fi

        stb_warn "Version mismatch: ${C_BOLD}${app_name}${C_RESET} installed=${installed_ver}, cask=${cask_ver}"
        stb_info "Reinstalling via Homebrew (--force replaces with cask version)..."

        local force_output force_exit
        force_output="$(brew install --cask "$cask_token" --force 2>&1)" && force_exit=0 || force_exit=$?

        if [ "$force_exit" -eq 0 ]; then
            stb_success "${app_name} switched to Homebrew (upgraded ${installed_ver} → ${cask_ver})"
            return 0
        else
            stb_error "Force-install also failed for ${app_name}:"
            echo "$force_output" | sed 's/^/    /' >&2
            return 1
        fi
    fi

    # Other unknown failure
    stb_error "Failed to adopt ${app_name}:"
    echo "$output" | sed 's/^/    /' >&2
    return 1
}

# ── Upgrade helper (called after successful adopt when --upgrade is set) ─────

_stb_maybe_upgrade() {
    local cask_token="$1"
    local app_name="$2"

    if [ "$STB_UPGRADE" != "true" ]; then
        return 0
    fi

    stb_info "Upgrading ${C_BOLD}${app_name}${C_RESET} to latest cask version..."

    local output exit_code
    output="$(brew upgrade --cask "$cask_token" 2>&1)" && exit_code=0 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        # brew upgrade exits 0 even when already up to date
        if echo "$output" | grep -q "already installed"; then
            stb_debug "${app_name} is already at the latest version"
        else
            stb_success "${app_name} upgraded to latest version"
        fi
    else
        stb_warn "Upgrade failed for ${app_name} (adopted successfully, upgrade manually with: brew upgrade --cask ${cask_token})"
        stb_debug "$output"
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
    local succeeded=0 failed=0 skipped=0 upgraded=0 force_adopted=0

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
