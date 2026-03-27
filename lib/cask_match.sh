#!/bin/bash
# switch-to-brew — cask name resolution
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

# ── Known mappings file ──────────────────────────────────────────────────────
# Loaded from data/known_casks.tsv at startup into flat files for grep-based
# lookup (avoiding bash 4 associative arrays for macOS compatibility).

STB_KNOWN_BY_BUNDLE=""  # path to temp file: bundle_id<TAB>cask_token
STB_KNOWN_BY_NAME=""    # path to temp file: app_name<TAB>cask_token

stb_cask_load_known() {
    local data_file="${STB_LIB_DIR}/../data/known_casks.tsv"
    [ -f "$data_file" ] || return 0

    STB_KNOWN_BY_BUNDLE="${STB_CACHE_DIR}/_known_by_bundle"
    STB_KNOWN_BY_NAME="${STB_CACHE_DIR}/_known_by_name"

    # Parse TSV: bundle_id \t cask_token \t app_name
    grep -v '^#' "$data_file" | grep -v '^$' | while IFS="$(printf '\t')" read -r bundle_id cask_token app_name; do
        [ -n "$bundle_id" ] && printf '%s\t%s\n' "$bundle_id" "$cask_token"
    done > "$STB_KNOWN_BY_BUNDLE"

    grep -v '^#' "$data_file" | grep -v '^$' | while IFS="$(printf '\t')" read -r bundle_id cask_token app_name; do
        [ -n "$app_name" ] && printf '%s\t%s\n' "$app_name" "$cask_token"
    done > "$STB_KNOWN_BY_NAME"

    local count
    count="$(wc -l < "$STB_KNOWN_BY_BUNDLE" | tr -d ' ')"
    stb_debug "Loaded ${count} known cask mappings."
}

# ── Resolve a single app to its Homebrew cask token ──────────────────────────
# Args: app_name  bundle_id
# Output: cask_token (or empty string if no match)
# Strategy:
#   1. Look up bundle_id in known_casks map  (instant)
#   2. Look up app_name in known_casks map   (instant)
#   3. Try normalised name variants against `brew search --cask`  (slow, cached)

stb_cask_resolve() {
    local app_name="$1"
    local bundle_id="$2"

    # Strategy 1: known map by bundle ID
    if [ -n "$STB_KNOWN_BY_BUNDLE" ] && [ -f "$STB_KNOWN_BY_BUNDLE" ]; then
        local match
        match="$(grep -F "$bundle_id" "$STB_KNOWN_BY_BUNDLE" | head -1 | cut -f2)"
        if [ -n "$match" ]; then
            echo "$match"
            return 0
        fi
    fi

    # Strategy 2: known map by app name (exact match)
    if [ -n "$STB_KNOWN_BY_NAME" ] && [ -f "$STB_KNOWN_BY_NAME" ]; then
        local match
        # Use awk for exact first-field match to avoid partial matches
        match="$(awk -F'\t' -v name="$app_name" '$1 == name {print $2; exit}' "$STB_KNOWN_BY_NAME")"
        if [ -n "$match" ]; then
            echo "$match"
            return 0
        fi
    fi

    # Strategy 3: normalise name and search brew
    local normalised
    normalised="$(stb_cask_normalise_name "$app_name")"

    # Check cache first
    local cached
    if cached="$(stb_cache_get "cask-${normalised}")"; then
        if [ "$cached" != "__NONE__" ]; then
            echo "$cached"
            return 0
        fi
        return 1
    fi

    # Search via brew API
    local search_output
    search_output="$(brew search --cask "$normalised" 2>/dev/null)" || true

    # Check for exact match in results
    local cask_token=""
    local line
    echo "$search_output" | while IFS= read -r line; do
        line="$(echo "$line" | sed 's/^==> Casks$//')"
        [ -z "$line" ] && continue
        if [ "$line" = "$normalised" ]; then
            echo "$line"
            return 0
        fi
    done
    # Capture from subshell
    cask_token="$(echo "$search_output" | grep -xF "$normalised" | head -1)"

    # If no exact match, try without trailing version number
    if [ -z "$cask_token" ]; then
        local variant
        variant="$(echo "$normalised" | sed -E 's/-[0-9]+$//')"
        if [ "$variant" != "$normalised" ]; then
            cask_token="$(echo "$search_output" | grep -xF "$variant" | head -1)"
        fi
    fi

    # Cache the result (even negative results to avoid repeated searches)
    if [ -n "$cask_token" ]; then
        echo "$cask_token" | stb_cache_set "cask-${normalised}"
        echo "$cask_token"
        return 0
    else
        echo "__NONE__" | stb_cache_set "cask-${normalised}"
        return 1
    fi
}

# Normalise an app name into a plausible Homebrew cask token:
#   "Visual Studio Code" → "visual-studio-code"
#   "1Password 7"        → "1password-7"
stb_cask_normalise_name() {
    local name="$1"
    echo "$name" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g' \
        | sed -E 's/^-+|-+$//g'
}

# ── Batch resolve ────────────────────────────────────────────────────────────
# Input: TSV lines from stb_discover_apps (app_name \t bundle_id \t path \t source)
# Output: TSV lines → app_name \t cask_token \t app_path \t source \t bundle_id
# Only outputs lines where a cask was found.

stb_cask_resolve_all() {
    local total=0 resolved=0 searched=0

    # Read all lines into a temp file (avoid subshell issues)
    local input_file="${STB_CACHE_DIR}/_resolve_input"
    cat > "$input_file"
    total="$(wc -l < "$input_file" | tr -d ' ')"

    stb_spinner_start "Matching ${total} $(stb_plural "$total" app) to Homebrew casks..."

    while IFS="$(printf '\t')" read -r app_name bundle_id app_path source; do
        [ -z "$app_name" ] && continue

        local cask_token
        if cask_token="$(stb_cask_resolve "$app_name" "$bundle_id")"; then
            printf '%s\t%s\t%s\t%s\t%s\n' "$app_name" "$cask_token" "$app_path" "$source" "$bundle_id"
            resolved=$((resolved + 1))
        fi
        searched=$((searched + 1))
        stb_debug "  [${searched}/${total}] ${app_name} → ${cask_token:-NONE}"
    done < "$input_file"

    stb_spinner_stop
    stb_info "Matched ${resolved} of ${total} $(stb_plural "$total" app) to Homebrew casks."

    rm -f "$input_file"
}
