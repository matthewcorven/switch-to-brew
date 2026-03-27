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

    # 1. Build a list of Homebrew-managed app names (one per line in a temp file)
    local managed_file="${STB_CACHE_DIR}/_managed_apps"
    brew list --cask -1 2>/dev/null > "$managed_file"

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

            # Skip if already managed by brew (case-insensitive match on app name
            # or normalised cask-style name)
            local norm_name
            norm_name="$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
            if grep -qixF "$app_name" "$managed_file" 2>/dev/null || \
               grep -qxF "$norm_name" "$managed_file" 2>/dev/null; then
                stb_debug "  skip (brew-managed): $app_name"
                continue
            fi

            # Get bundle identifier
            local bundle_id
            bundle_id="$(defaults read "${app_path}/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "")"

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
