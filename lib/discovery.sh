#!/bin/bash
# switch-to-brew — app discovery and filtering
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

# Discover all .app bundles that are:
#   - Not Apple/system apps (by bundle ID)
#   - Not already managed by Homebrew
#   - Not Mac App Store installs (unless requested)
#   - Not in the skip-patterns list
#
# Output: TSV lines → app_name \t bundle_id \t app_path \t source
#   source = "manual" | "app-store" | "setapp"

stb_discover_apps() {
    local include_app_store="${1:-false}"

    # 1. Build a list of Homebrew-managed identifiers (cask tokens + app names)
    local managed_file="${STB_CACHE_DIR}/_managed_apps"
    brew list --cask -1 2>/dev/null > "$managed_file"
    local managed_formula_file="${STB_CACHE_DIR}/_managed_formulae"
    brew list -1 2>/dev/null > "$managed_formula_file"

    # Resolve cask tokens → app names via known_casks.tsv so we can match
    # apps whose name differs from the cask token (e.g. iTerm → iterm2,
    # DisplayLink Manager → displaylink)
    local known_file="${STB_SCRIPT_DIR}/data/known_casks.tsv"
    if [ -f "$known_file" ] && [ -f "$managed_file" ]; then
        local tokens_copy="${STB_CACHE_DIR}/_managed_tokens"
        cp "$managed_file" "$tokens_copy"
        local cask_token
        while IFS= read -r cask_token; do
            [ -z "$cask_token" ] && continue
            local mapped_name
            mapped_name="$(awk -F'\t' -v t="$cask_token" '($4 == "" || $4 == "cask") && $2 == t { print $3 }' "$known_file" 2>/dev/null)"
            if [ -n "$mapped_name" ]; then
                echo "$mapped_name" >> "$managed_file"
            fi
        done < "$tokens_copy"
        rm -f "$tokens_copy"
    fi

    if [ -f "$known_file" ] && [ -f "$managed_formula_file" ]; then
        local formulas_copy="${STB_CACHE_DIR}/_managed_formula_tokens"
        cp "$managed_formula_file" "$formulas_copy"
        local formula_token
        while IFS= read -r formula_token; do
            [ -z "$formula_token" ] && continue
            local mapped_name
            mapped_name="$(awk -F'\t' -v t="$formula_token" '
                {
                    type = ($4 == "" ? "cask" : $4)
                    short = $2
                    sub(/^.*\//, "", short)
                    if (type == "formula" && (t == $2 || t == short)) {
                        print $3
                    }
                }
            ' "$known_file" 2>/dev/null)"
            if [ -n "$mapped_name" ]; then
                echo "$mapped_name" >> "$managed_file"
            fi
        done < "$formulas_copy"
        rm -f "$formulas_copy"
    fi

    # Also add .app names found in the caskroom
    local caskroom
    caskroom="$(brew --caskroom 2>/dev/null)"
    if [ -d "$caskroom" ]; then
        for cask_dir in "$caskroom"/*/; do
            [ -d "$cask_dir" ] || continue
            local app_name
            app_name="$(find "$cask_dir" -maxdepth 3 -name "*.app" -type d 2>/dev/null | head -1)"
            if [ -n "$app_name" ]; then
                basename "$app_name" .app >> "$managed_file"
            fi
        done
    fi

    # 2. Scan application directories
    local dir
    for dir in $STB_APP_DIRS; do
        [ -d "$dir" ] || continue
        stb_debug "Scanning ${dir}..."

        for app_path in "$dir"/*.app; do
            [ -d "$app_path" ] || continue
            local app_name
            app_name="$(basename "$app_path" .app)"

            # Get bundle identifier (needed for multiple checks below)
            local bundle_id
            bundle_id="$(defaults read "${app_path}/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "")"

            # Skip if already managed by brew:
            #   1. Case-insensitive match on app name (e.g. "Docker" matches "docker")
            #   2. Normalised cask-style name (e.g. "visual-studio-code")
            #   3. Known cask token for this bundle ID (catches renamed casks)
            local norm_name
            norm_name="$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
            if grep -qixF "$app_name" "$managed_file" 2>/dev/null || \
               grep -qxF "$norm_name" "$managed_file" 2>/dev/null; then
                stb_debug "  skip (brew-managed): $app_name"
                continue
            fi
            if [ -n "$bundle_id" ] && [ -f "$known_file" ]; then
                local known_token known_type known_short
                known_token="$(awk -F'\t' -v b="$bundle_id" '$1 == b { print $2 }' "$known_file" 2>/dev/null)"
                known_type="$(awk -F'\t' -v b="$bundle_id" '$1 == b { print ($4 == "" ? "cask" : $4) }' "$known_file" 2>/dev/null)"
                [ -z "$known_type" ] && known_type="cask"
                if [ -n "$known_token" ]; then
                    if [ "$known_type" = "formula" ]; then
                        known_short="$(echo "$known_token" | awk -F/ '{print $NF}')"
                        if grep -qxF "$known_token" "$managed_formula_file" 2>/dev/null || \
                           grep -qxF "$known_short" "$managed_formula_file" 2>/dev/null; then
                            stb_debug "  skip (brew-managed via known formula): $app_name ($known_token)"
                            continue
                        fi
                    elif grep -qxF "$known_token" "$managed_file" 2>/dev/null; then
                        stb_debug "  skip (brew-managed via known cask): $app_name ($known_token)"
                        continue
                    fi
                fi
            fi

            # Skip system apps by bundle ID prefix
            case "$bundle_id" in
                "${STB_SYSTEM_PREFIX}"*)
                    stb_debug "  skip (system): $app_name ($bundle_id)"
                    continue
                    ;;
            esac

            # Skip installers, helpers, shims
            case "$app_name" in
                Install\ *|Uninstall\ *|*\ Installer|*\ Helper|*\ Updater|Microsoft\ Defender\ Shim)
                    stb_debug "  skip (pattern): $app_name"
                    continue
                    ;;
            esac

            # Determine source
            local source="manual"
            if stb_is_app_store_app "$app_path"; then
                source="app-store"
                if [ "$include_app_store" != "true" ]; then
                    stb_debug "  skip (App Store): $app_name"
                    continue
                fi
            fi

            # Check for Setapp
            if [ -d "${app_path}/Contents/Frameworks/Setapp.framework" ]; then
                source="setapp"
            fi
            case "$bundle_id" in
                *.setapp*) source="setapp" ;;
            esac

            printf '%s\t%s\t%s\t%s\n' "$app_name" "$bundle_id" "$app_path" "$source"
        done
    done | sort -t"$(printf '\t')" -f -k1,1
}
