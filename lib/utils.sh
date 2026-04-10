#!/bin/bash

# ==============================================================================
#  FORBCHECK UTILS MODULE (Low-level Helpers)
# ==============================================================================

realpath_portable() {
    local target="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$target"
    else
        if [ -d "$target" ]; then
            (cd "$target" && pwd)
        elif [ -f "$target" ]; then
            (cd "$(dirname "$target")" && echo "$(pwd)/$(basename "$target")")
        else
            echo "$target"
        fi
    fi
}

get_file_mtime() {
    if [ "$IS_MAC" = true ]; then
        stat -f %m "$1" 2>/dev/null || echo 0
    else
        stat -c %Y "$1" 2>/dev/null || echo 0
    fi
}

get_file_size() {
    if [ "$IS_MAC" = true ]; then
        stat -f %z "$1" 2>/dev/null || echo 0
    else
        stat -c %s "$1" 2>/dev/null || echo 0
    fi
}

get_file_size_all_src() {
    if [ "$IS_MAC" = true ]; then
        find . -name "*.c" -not -path '*/.*' -type f -exec stat -f "%z" {} + 2>/dev/null | awk '{s+=$1} END {print s+0}'
    else
        find . -name "*.c" -not -path '*/.*' -type f -exec stat -c "%s" {} + 2>/dev/null | awk '{s+=$1} END {print s+0}'
    fi
}

get_timestamp() {
    if [ "$IS_MAC" = true ]; then
        perl -MTime::HiRes=time -e 'print time'
    else
        date +%s.%N
    fi
}

calculate_duration() {
    local start="$1"
    local end="$2"
    local dur=$(echo "$end - $start" | bc 2>/dev/null || echo "0")
    # Add leading zero if needed
    [[ "$dur" == .* ]] && dur="0${dur}"
    # Truncate to 3 decimal places
    echo "$dur" | awk '{printf "%.3f", $1}'
}

center_log() {
    local text="$1"
    local width=49
    # Strip ANSI colors to calculate real length
    local plain=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#plain}
    local pad=$(( (width - len) / 2 ))
    local spaces=""
    for ((i=0; i<pad; i++)); do spaces+=" "; done
    log_info "${spaces}${text}"
}

safe_exit() {
    local exit_code=${1:-0}
    if [ "$PUT_LOG" = true ] && [ -n "$LOG_FILE" ] && [ "$USE_JSON" = false ] && [ "$USE_GRAPH" = false ]; then
        echo -e "\n${BLUE}ℹ Scan log saved to: ${YELLOW}$LOG_FILE${NC}"
    fi
    exit "$exit_code"
}

log_info() {
    if [ "$USE_JSON" != true ] && [ "$USE_HTML" != true ] && [ "$USE_GRAPH" != true ]; then
        if [ "$PUT_LOG" = true ] && [ -n "$LOG_FILE" ]; then
            echo -e "$@" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
        else
            echo -e "$@"
        fi
    fi
}

version_to_int() {
    echo "$1" | sed 's/v//' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }'
}

get_core_count() {
    if [ "$IS_MAC" = true ]; then
        sysctl -n hw.ncpu 2>/dev/null || echo 2
    else
        nproc 2>/dev/null || echo 2
    fi
}

crop_line() {
    local func="$1"
    local code="$2"
    local display_code="$code"

    if [ ${#code} -gt 65 ]; then
        local prefix="${code%%$func*}"
        local pos=${#prefix}
        local start=$((pos > 20 ? pos - 20 : 0))
        display_code="...${code:$start:100}..."
    fi

    local final_code="${display_code//$func/$RED$BOLD$func$NC$CYAN}"
    echo -e "$final_code"
}

clean_code_snippet() {
    local snippet="$1"
    local f_name="$2"
    local safe_name=$(printf '%s\n' "$f_name" | sed 's/[.[\*^$]/\\&/g')

    snippet=$(echo "$snippet" | sed 's|//.*||')
    snippet=$(echo "$snippet" | sed 's|/\*.*\*/||g')

    if echo "$snippet" | grep -qE "\b${safe_name}\b"; then
        echo "$snippet"
        return 0
    else
        return 1
    fi
}
