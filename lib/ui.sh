#!/bin/bash
# switch-to-brew — interactive selection UI
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

# ── Render discovery results table ───────────────────────────────────────────

stb_ui_print_table() {
    local show_index="${1:-false}"
    local idx=0

    # Header
    if [ "$show_index" = "true" ]; then
        printf '%s  #   %-34s %-36s %s%s\n' \
            "${C_BOLD}" "Application" "Cask" "Source" "${C_RESET}"
        printf '  '
        printf '─%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
            21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 \
            41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 \
            61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 \
            81 82 83 84 85 86 87 88 89 90
        printf '\n'
    else
        printf '%s  %-34s %-36s %s%s\n' \
            "${C_BOLD}" "Application" "Cask" "Source" "${C_RESET}"
        printf '  '
        printf '─%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
            21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 \
            41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 \
            61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80
        printf '\n'
    fi

    while IFS="$(printf '\t')" read -r app_name cask_token app_path source bundle_id; do
        idx=$((idx + 1))
        local source_badge
        case "$source" in
            app-store) source_badge="${C_BLUE}App Store${C_RESET}" ;;
            setapp)    source_badge="${C_YELLOW}Setapp${C_RESET}" ;;
            *)         source_badge="${C_DIM}manual${C_RESET}" ;;
        esac

        if [ "$show_index" = "true" ]; then
            printf '  %s%-3d%s %-34s %s%-36s%s %s\n' \
                "${C_CYAN}" "$idx" "${C_RESET}" \
                "$app_name" \
                "${C_GREEN}" "$cask_token" "${C_RESET}" \
                "$source_badge"
        else
            printf '  %-34s %s%-36s%s %s\n' \
                "$app_name" \
                "${C_GREEN}" "$cask_token" "${C_RESET}" \
                "$source_badge"
        fi
    done
}

# ── Interactive picker ───────────────────────────────────────────────────────
# Input on stdin: resolved TSV lines (same format as cask_resolve_all output)
# Output on stdout: selected lines in same TSV format
# Returns 1 if user cancels

stb_ui_select() {
    # Read lines into a temp file (bash 3.2 can't do mapfile)
    local lines_file="${STB_CACHE_DIR}/_select_lines"
    cat > "$lines_file"

    local count
    count="$(wc -l < "$lines_file" | tr -d ' ')"
    if [ "$count" -eq 0 ]; then
        stb_warn "Nothing to select."
        rm -f "$lines_file"
        return 1
    fi

    echo "" >&2
    stb_ui_print_table true < "$lines_file" >&2
    echo "" >&2

    printf '%s%sSelect apps to switch to Homebrew:%s\n' "${C_BOLD}" "${C_WHITE}" "${C_RESET}" >&2
    printf '  %sEnter numbers separated by spaces (e.g. 1 3 5)%s\n' "${C_DIM}" "${C_RESET}" >&2
    printf '  %sRanges work too (e.g. 1-5 8 10-12)%s\n' "${C_DIM}" "${C_RESET}" >&2
    printf '  %sType "all" to select everything, "q" to cancel%s\n' "${C_DIM}" "${C_RESET}" >&2
    echo "" >&2

    local selection
    printf '%s❯%s ' "${C_CYAN}" "${C_RESET}" >&2
    read -r selection < /dev/tty

    if [ -z "$selection" ] || [ "$selection" = "q" ] || [ "$selection" = "quit" ]; then
        rm -f "$lines_file"
        return 1
    fi

    # Build list of selected line numbers
    local selected_nums=""

    if [ "$selection" = "all" ] || [ "$selection" = "a" ]; then
        local i=1
        while [ "$i" -le "$count" ]; do
            selected_nums="$selected_nums $i"
            i=$((i + 1))
        done
    else
        # Parse selection: support "1 3 5", "1-5", "1-3 7 9-12"
        for token in $selection; do
            case "$token" in
                *-*)
                    local range_start range_end i
                    range_start="$(echo "$token" | cut -d- -f1)"
                    range_end="$(echo "$token" | cut -d- -f2)"
                    if [ -n "$range_start" ] && [ -n "$range_end" ]; then
                        i="$range_start"
                        while [ "$i" -le "$range_end" ] && [ "$i" -le "$count" ]; do
                            [ "$i" -ge 1 ] && selected_nums="$selected_nums $i"
                            i=$((i + 1))
                        done
                    fi
                    ;;
                *[0-9]*)
                    if [ "$token" -ge 1 ] 2>/dev/null && [ "$token" -le "$count" ] 2>/dev/null; then
                        selected_nums="$selected_nums $token"
                    fi
                    ;;
            esac
        done
    fi

    # Deduplicate
    selected_nums="$(echo "$selected_nums" | tr ' ' '\n' | sort -un | tr '\n' ' ')"

    if [ -z "$(echo "$selected_nums" | tr -d ' ')" ]; then
        stb_warn "No valid selection."
        rm -f "$lines_file"
        return 1
    fi

    # Output selected lines
    for num in $selected_nums; do
        sed -n "${num}p" "$lines_file"
    done

    rm -f "$lines_file"
}
