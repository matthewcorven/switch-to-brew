#!/bin/bash
# switch-to-brew — constants and configuration
# Compatible with macOS default bash (3.2+)
# shellcheck shell=bash

STB_VERSION="1.0.0"
STB_NAME="switch-to-brew"

# ── Exit codes ───────────────────────────────────────────────────────────────
EXIT_OK=0
EXIT_ERR=1
EXIT_USAGE=2
EXIT_NO_BREW=3
EXIT_NO_RESULTS=4

# ── Paths ────────────────────────────────────────────────────────────────────
STB_CACHE_DIR="${TMPDIR:-/tmp}/${STB_NAME}-${USER:-unknown}"
STB_CACHE_TTL=300  # seconds before cache is considered stale

# ── App directories to scan ──────────────────────────────────────────────────
STB_APP_DIRS="/Applications ${HOME}/Applications"

# ── Bundle ID prefix that identifies system / Apple apps ─────────────────────
STB_SYSTEM_PREFIX="com.apple."

# ── App name patterns to always skip (checked with case statement) ───────────
# Handled in discovery.sh via case matching

# ── Colors (disabled when NO_COLOR is set or stdout is not a terminal) ───────
if [ -z "${NO_COLOR:-}" ] && [ -z "${STB_NO_COLOR:-}" ] && [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_WHITE=$'\033[37m'
    C_BG_GREEN=$'\033[42m'
    C_BG_BLUE=$'\033[44m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_CYAN="" C_WHITE="" C_BG_GREEN="" C_BG_BLUE=""
fi
