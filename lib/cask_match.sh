#!/bin/bash
# switch-to-brew — Homebrew package resolution
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

# ── Known mappings file ──────────────────────────────────────────────────────
# Loaded from data/known_casks.tsv at startup into flat files for grep-based
# lookup (avoiding bash 4 associative arrays for macOS compatibility).

STB_KNOWN_BY_BUNDLE=""  # path to temp file: bundle_id<TAB>brew_token<TAB>package_type
STB_KNOWN_BY_NAME=""    # path to temp file: app_name<TAB>brew_token<TAB>package_type

stb_cask_load_known() {
    local data_file="${STB_LIB_DIR}/../data/known_casks.tsv"
    [ -f "$data_file" ] || return 0

    STB_KNOWN_BY_BUNDLE="${STB_CACHE_DIR}/_known_by_bundle"
    STB_KNOWN_BY_NAME="${STB_CACHE_DIR}/_known_by_name"

    # Parse TSV: bundle_id \t brew_token \t app_name \t package_type(optional)
    grep -v '^#' "$data_file" | grep -v '^$' | while IFS="$(printf '\t')" read -r bundle_id cask_token app_name package_type; do
        [ -z "$package_type" ] && package_type="cask"
        [ -n "$bundle_id" ] && printf '%s\t%s\t%s\n' "$bundle_id" "$cask_token" "$package_type"
    done > "$STB_KNOWN_BY_BUNDLE"

    grep -v '^#' "$data_file" | grep -v '^$' | while IFS="$(printf '\t')" read -r bundle_id cask_token app_name package_type; do
        [ -z "$package_type" ] && package_type="cask"
        [ -n "$app_name" ] && printf '%s\t%s\t%s\n' "$app_name" "$cask_token" "$package_type"
    done > "$STB_KNOWN_BY_NAME"

    local count
    count="$(wc -l < "$STB_KNOWN_BY_BUNDLE" | tr -d ' ')"
    stb_debug "Loaded ${count} known Homebrew mappings."
}

# ── Validate a Homebrew package actually exists ───────────────────────────────
# Uses `brew info` with result caching to avoid repeated API calls.
# Returns 0 if valid, 1 if not.

stb_brew_package_exists() {
    local token="$1"
    local package_type="${2:-cask}"
    local token_key
    token_key="$(echo "$token" | sed 's#[^A-Za-z0-9._-]#_#g')"

    # Check positive/negative cache first
    local cached
    if cached="$(stb_cache_get "exists-${package_type}-${token_key}" 2>/dev/null)"; then
        [ "$cached" = "yes" ] && return 0
        return 1
    fi

    if [ "$package_type" = "formula" ]; then
        if brew info "$token" >/dev/null 2>&1; then
            echo "yes" | stb_cache_set "exists-${package_type}-${token_key}"
            return 0
        fi
    elif brew info --cask "$token" >/dev/null 2>&1; then
        echo "yes" | stb_cache_set "exists-${package_type}-${token_key}"
        return 0
    fi

    echo "no" | stb_cache_set "exists-${package_type}-${token_key}"
    stb_debug "  ${package_type} '${token}' does not exist in Homebrew"
    return 1
}

stb_brew_detect_package_type() {
    local token="$1"

    if brew info --cask "$token" >/dev/null 2>&1; then
        echo "cask"
        return 0
    fi

    if brew info "$token" >/dev/null 2>&1; then
        echo "formula"
        return 0
    fi

    echo "cask"
    return 0
}

# ── Resolve a single app to its Homebrew package token ───────────────────────
# Args: app_name  bundle_id
# Output: brew_token<TAB>package_type (or empty string if no match)
# Strategy:
#   1. Look up bundle_id in known_casks map  (instant)
#   2. Look up app_name in known_casks map   (instant)
#   3. Try normalised name variants against `brew search --cask`  (slow, cached)

stb_cask_resolve() {
    local app_name="$1"
    local bundle_id="$2"

    # Strategy 1: known map by bundle ID
    if [ -n "$STB_KNOWN_BY_BUNDLE" ] && [ -f "$STB_KNOWN_BY_BUNDLE" ]; then
        local match match_type
        match="$(awk -F'\t' -v bundle_id="$bundle_id" '$1 == bundle_id {print $2; exit}' "$STB_KNOWN_BY_BUNDLE")"
        match_type="$(awk -F'\t' -v bundle_id="$bundle_id" '$1 == bundle_id {print $3; exit}' "$STB_KNOWN_BY_BUNDLE")"
        [ -z "$match_type" ] && match_type="cask"
        if [ -n "$match" ] && stb_brew_package_exists "$match" "$match_type"; then
            printf '%s\t%s\n' "$match" "$match_type"
            return 0
        fi
    fi

    # Strategy 2: known map by app name (exact match)
    if [ -n "$STB_KNOWN_BY_NAME" ] && [ -f "$STB_KNOWN_BY_NAME" ]; then
        local match match_type
        # Use awk for exact first-field match to avoid partial matches
        match="$(awk -F'\t' -v name="$app_name" '$1 == name {print $2; exit}' "$STB_KNOWN_BY_NAME")"
        match_type="$(awk -F'\t' -v name="$app_name" '$1 == name {print $3; exit}' "$STB_KNOWN_BY_NAME")"
        [ -z "$match_type" ] && match_type="cask"
        if [ -n "$match" ] && stb_brew_package_exists "$match" "$match_type"; then
            printf '%s\t%s\n' "$match" "$match_type"
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
        printf '%s\t%s\n' "$cask_token" "cask"
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
# Output: TSV lines → app_name \t brew_token \t app_path \t source \t bundle_id \t package_type
# Only outputs lines where a Homebrew package was found.

stb_cask_resolve_all() {
    local total=0 resolved=0 searched=0

    # Read all lines into a temp file (avoid subshell issues)
    local input_file="${STB_CACHE_DIR}/_resolve_input"
    cat > "$input_file"
    total="$(wc -l < "$input_file" | tr -d ' ')"

    stb_spinner_start "Matching ${total} $(stb_plural "$total" app) to Homebrew packages..."

    while IFS="$(printf '\t')" read -r app_name bundle_id app_path source; do
        [ -z "$app_name" ] && continue

        local package_info cask_token package_type
        if package_info="$(stb_cask_resolve "$app_name" "$bundle_id")"; then
            cask_token="$(echo "$package_info" | cut -f1)"
            package_type="$(echo "$package_info" | cut -f2)"
            [ -z "$package_type" ] && package_type="cask"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$app_name" "$cask_token" "$app_path" "$source" "$bundle_id" "$package_type"
            resolved=$((resolved + 1))
        fi
        searched=$((searched + 1))
        stb_debug "  [${searched}/${total}] ${app_name} → ${cask_token:-NONE}"
    done < "$input_file"

    stb_spinner_stop
    stb_info "Matched ${resolved} of ${total} $(stb_plural "$total" app) to Homebrew packages."

    rm -f "$input_file"
}
