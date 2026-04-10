#!/bin/bash

# ==============================================================================
#  FORBCHECK UI MODULE (Colors, Help, Banner)
# ==============================================================================

# Colors Configuration
if [[ -t 1 ]]; then
    BOLD="\033[1m"; GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; CYAN="\033[0;36m"; NC="\033[0m"
else
    BOLD=""; GREEN=""; RED=""; YELLOW=""; BLUE=""; CYAN=""; NC=""
fi

show_banner() {
    log_info "${YELLOW}╔═════════════════════════════════════╗${NC}"
    log_info "${YELLOW}║              ForbCheck              ║${NC}"
    log_info "${YELLOW}╚═════════════════════════════════════╝${NC}"
}

show_help() {
    echo -e "${BOLD}ForbCheck v$VERSION${NC}"
    echo -e "Usage: forb [options] <target> [-f <files...>]\n"

    echo -e "${BOLD}Arguments:${NC}"
    printf "  %-24s %s\n" "<target>" "Executable or library to analyze"

    echo -e "\n${BOLD}General:${NC}"
    printf "  %-24s %s\n" "-h, --help" "Show help message"
    printf "  %-24s %s\n" "--json" "Generate a JSON output for automations"
    printf "  %-24s %s\n" "--html" "Generate a beautiful interactive HTML report"
    printf "  %-24s %s\n" "--graph" "Generate an interactive D3.js call graph HTML report"
    printf "  %-24s %s\n" "-oh, --open-html" "Open the folder containing HTML reports"
    printf "  %-24s %s\n" "-ol, --open-logs" "Open the folder containing log files"
    printf "  %-24s %s\n" "--log" "Generate a .log of the output"
    printf "  %-24s %s\n" "-l, --list [<funcs...>]" "Show list or check specific functions"
    printf "  %-24s %s\n" "-e, --edit" "Edit authorized list"

    echo -e "\n${BOLD}Presets:${NC}"
    printf "  %-24s %s\n" "-P, --preset" "Load the preset matching the target name"
    printf "  %-24s %s\n" "-np, --no-preset" "Disable auto-preset and force default list"
    printf "  %-24s %s\n" "-gp, --get-presets" "Restore default presets (overwrites matches)"
    printf "  %-24s %s\n" "-cp, --create-preset" "Create and edit a new preset"
    printf "  %-24s %s\n" "-lp, --list-presets" "Show all presets"
    printf "  %-24s %s\n" "-op, --open-presets" "Open presets directory"
    printf "  %-24s %s\n" "-rp, --remove-preset" "Delete an existing preset"

    echo -e "\n${BOLD}Scan Options:${NC}"
    printf "  %-24s %s\n" "-b, --blacklist" "Force Blacklist Mode (Hunt specific functions instead of whitelist)"
    printf "  %-24s %s\n" "-v, --verbose" "Show source code context"
    printf "  %-24s %s\n" "-f <files...>" "Limit scan to specific files"
    printf "  %-24s %s\n" "-p, --full-path" "Show full paths"
    printf "  %-24s %s\n" "-a, --all" "Show authorized functions during scan"
    printf "  %-24s %s\n" "--no-auto" "Disable auto-detection (must be used BEFORE -s)"

    echo -e "\n${BOLD}Deep Scan:${NC}"
    printf "  %-24s %s\n" "-s, --source" "Scan source files for unauthorized C functions"

    printf "  %-24s %s\n" "-lm" "Ignore Math library internal calls"

    echo -e "\n${BOLD}Analysis:${NC}"
    printf "  %-24s %s\n" "-A, --analyse" "Open interactive project analysis dashboard"

    echo -e "\n${BOLD}Maintenance:${NC}"
    printf "  %-24s %s\n" "-t, --time" "Show execution duration"
    printf "  %-24s %s\n" "--version" "Show version's forbCheck"
    printf "  %-24s %s\n" "-up, --update" "Check and install latest version"
    printf "  %-24s %s\n" "--remove" "Remove ForbCheck"
    safe_exit 0
}
