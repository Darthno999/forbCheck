#!/bin/bash

# ==============================================================================
#  ForbCheck - Main Entry Point
# ==============================================================================

# Constants
readonly VERSION="1.16.0" # Interactive analysis
readonly INSTALL_DIR="$HOME/.forb"
readonly LOG_DIR="$HOME/.forb/logs"
readonly PRESET_DIR="$INSTALL_DIR/presets"
readonly UPDATE_URL="https://raw.githubusercontent.com/Mrdolls/forb/refs/heads/main/forb.sh"

# Global State Variables (Mutable)
ACTIVE_PRESET="$PRESET_DIR/default.preset"
LOG_FILE=""
USE_JSON=false
USE_HTML=false
USE_GRAPH=false
USE_PRESET=0
SHOW_ALL=false
USE_MLX=false
USE_MATH=false
BLACKLIST_MODE=false
FULL_PATH=false
VERBOSE=false
TARGET=""
SPECIFIC_FILES=""
SHOW_TIME=false
DISABLE_AUTO=false
DISABLE_PRESET=false
SET_WARNING=false
PUT_LOG=false

SHOW_HELP=false
SHOW_VERSION=false
DO_UPDATE=false
DO_REMOVE=false
DO_GET_PRESETS=false
DO_LIST_PRESETS=false
DO_OPEN_PRESETS=false
DO_OPEN_HTML=false
DO_OPEN_LOGS=false
DO_CREATE_PRESET=false
DO_REMOVE_PRESET=false
DO_EDIT_LIST=false
RUN_LIST=false
LIST_FUNCS=""
DO_ANALYSE=false

# OS Detection
if [[ "$OSTYPE" == "darwin"* ]]; then readonly IS_MAC=true; else readonly IS_MAC=false; fi

# Load Modules
for module in ui.sh utils.sh presets.sh scan.sh analyse.sh output_generator.sh maintenance.sh html_generator.sh graph_generator.sh; do
    if [ -f "$INSTALL_DIR/lib/$module" ]; then
        source "$INSTALL_DIR/lib/$module"
    else
        echo "Error: Missing module $INSTALL_DIR/lib/$module"
        exit 1
    fi
done

# Initialize Structure
bootstrap_directories() {
    local dirs=("doc" "presets" "lib" "cache" "logs" "reports_html" "reports_graph")
    for d in "${dirs[@]}"; do
        mkdir -p "$INSTALL_DIR/$d"
    done
}
bootstrap_directories

# 1. Pre-process arguments
args=()
for arg in "$@"; do
    if [[ "$arg" =~ ^-(mlx|lm|up|op|lp|cp|rp|gp|np|oh|ol)$ ]]; then args+=("$arg")
    elif [[ "$arg" == "--"* ]]; then args+=("$arg")
    elif [[ "$arg" =~ ^-[a-zA-Z]{2,}$ ]]; then
        _i=1
        while (( _i < ${#arg} )); do
            _two="${arg:$_i:2}"
            if [[ "$_two" =~ ^(np|na|lm|up|op|lp|cp|rp|gp|mlx|oh|ol)$ ]]; then args+=("-$_two"); _i=$(( _i + 2 ))
            else args+=("-${arg:$_i:1}"); _i=$(( _i + 1 )); fi
        done
    else args+=("$arg"); fi
done
set -- "${args[@]}"

# 2. Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) SHOW_HELP=true; shift ;;
        --version) SHOW_VERSION=true; shift ;;
        --json) USE_JSON=true; shift ;;
        --html) USE_HTML=true; shift ;;
        --graph) USE_GRAPH=true; shift ;;
        --log) PUT_LOG=true; shift ;;
        -up|--update) DO_UPDATE=true; shift ;;
        --remove) DO_REMOVE=true; shift ;;
        --no-auto) DISABLE_AUTO=true; shift ;;
        -A|--analyse) DO_ANALYSE=true; shift ;;
        -b|--blacklist) export BLACKLIST_MODE=true; shift ;;
        -s|--source) FORCE_SOURCE_SCAN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -p|--full-path) FULL_PATH=true; shift ;;
        -a|--all) SHOW_ALL=true; shift ;;
        -mlx) USE_MLX=true; shift ;;
        -lm) USE_MATH=true; shift ;;
        --preset|-P) USE_PRESET=1; shift ;;
        -np|--no-preset) DISABLE_PRESET=true; shift ;;
        -gp|--get-presets) DO_GET_PRESETS=true; shift ;;
        -lp|--list-presets) DO_LIST_PRESETS=true; shift ;;
        -op|--open-presets) DO_OPEN_PRESETS=true; shift ;;
        -oh|--open-html) DO_OPEN_HTML=true; shift ;;
        -ol|--open-logs) DO_OPEN_LOGS=true; shift ;;
        -cp|--create-preset) DO_CREATE_PRESET=true; shift ;;
        -rp|--remove-preset) DO_REMOVE_PRESET=true; shift ;;
        -e|--edit) DO_EDIT_LIST=true; shift ;;
        -l|--list)
            RUN_LIST=true; shift
            while [[ $# -gt 0 && ! "$1" =~ ^- && ! -f "$1" ]]; do
                if [[ $# -eq 1 && -f "$PRESET_DIR/${1}.preset" ]]; then TARGET="$1"; shift; break; fi
                LIST_FUNCS+="$1 "; shift
            done
            continue ;;
        -t|--time) SHOW_TIME=true; shift ;;
        -f)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                if [[ $# -eq 1 && ! -f "$1" && "$1" != *.c && "$1" != *.cpp && "$1" != *\* ]]; then TARGET="$1"; shift; break; fi
                SPECIFIC_FILES+="$1 "; shift
            done
            continue ;;
        -*) echo -e "${RED}Unknown option: $1${NC}"; safe_exit 1 ;;
        *) TARGET=$1; shift ;;
    esac
done

# 3. Handle specific commands
if [ "$SHOW_HELP" = true ]; then show_help; fi
if [ "$SHOW_VERSION" = true ]; then log_info "V$VERSION"; safe_exit 0; fi
if [ "$DO_UPDATE" = true ]; then update_script; safe_exit 0; fi
if [ "$DO_REMOVE" = true ]; then uninstall_script; fi
if [ "$DO_GET_PRESETS" = true ]; then get_presets "manual"; fi
if [ "$DO_LIST_PRESETS" = true ]; then list_presets; fi
if [ "$DO_OPEN_PRESETS" = true ]; then open_presets; fi
if [ "$DO_OPEN_HTML" = true ]; then open_html; fi
if [ "$DO_OPEN_LOGS" = true ]; then open_logs; fi
if [ "$DO_CREATE_PRESET" = true ]; then create_preset; fi
if [ "$DO_REMOVE_PRESET" = true ]; then remove_preset; fi
if [ "$DO_ANALYSE" = true ]; then start_analysis; fi

# 4. Initialize Logs
if [ "$PUT_LOG" = true ]; then
    [ "$USE_JSON" != true ] && [ "$USE_HTML" != true ] && [ "$USE_GRAPH" != true ] && echo -e "${CYAN}Logging to $LOG_DIR...${NC}"
    LOG_FILE="$LOG_DIR/l$(( $(ls -1 "$LOG_DIR"/*.log 2>/dev/null | wc -l) + 1 ))_$(date +"%Y-%m-%d_%Hh%M").log"
fi

# 5. Core Execution
check_dependencies
show_banner

if [ "$FORCE_SOURCE_SCAN" = true ]; then source_scan; fi

if [ -z "$TARGET" ]; then
    if [ "$DISABLE_AUTO" = true ]; then
        if [ "$DO_EDIT_LIST" != true ] && [ "$RUN_LIST" != true ]; then
            if [ "$USE_JSON" = true ]; then
                echo "{\"status\":\"FAILURE\",\"error\":\"No target\"}"
            elif [ "$USE_HTML" = true ] || [ "$USE_GRAPH" = true ]; then
                echo "Error: No target specified."
            else
                log_info "${RED}Error: No target specified.${NC}"
            fi
            safe_exit 1
        fi
    elif ! auto_detect_target; then
        if [ "$DO_EDIT_LIST" != true ] && [ "$RUN_LIST" != true ]; then
            log_info "${RED}[Auto-Detect] No binary found.${YELLOW} -> Falling back to Source Scan...${NC}\n"
            source_scan
        fi
    fi
elif [ ! -f "$TARGET" ]; then
    if [ "$DO_EDIT_LIST" != true ] && [ "$RUN_LIST" != true ]; then
        log_info "${YELLOW}[Warning] Target '$TARGET' not found. Falling back to Source Scan...${NC}\n"
        source_scan
    fi
fi

auto_check_update

if [ "$DO_EDIT_LIST" = true ] || [ "$RUN_LIST" = true ]; then
    resolve_preset "list"; load_preset "$SELECTED_PRESET"
    [ "$DO_EDIT_LIST" = true ] && edit_list
    [ "$RUN_LIST" = true ] && process_list $LIST_FUNCS
fi

check_binary_cache
auto_detect_libraries
resolve_preset "binary"; load_preset "$SELECTED_PRESET"
parse_preset_flags "$(cat "$ACTIVE_PRESET" 2>/dev/null)"

# Report Execution Details
log_info "${BLUE}Scan Mode  :${NC} ${YELLOW}Binary${NC}"
log_info "${BLUE}Preset     :${NC} ${BOLD}${SELECTED_PRESET}${NC} ${CYAN}($( [ "$BLACKLIST_MODE" = true ] && echo "Blacklist" || echo "Whitelist" ))${NC}"
[ "$SET_WARNING" = true ] && log_info "${YELLOW}Warning:${NC} Source content is newer than the binary."
[ -n "$SPECIFIC_FILES" ] && log_info "${BLUE}Scope      :${NC} $SPECIFIC_FILES"

log_info "\n${BLUE}${BOLD}Execution:${NC}\n-------------------------------------------------"

START_TIME=$(get_timestamp)

run_analysis
total_errors=$?

DURATION=$(calculate_duration "$START_TIME" "$(get_timestamp)")

log_info "\n-------------------------------------------------"
if [ "$FORBIDDEN_COUNT" -gt 0 ]; then
    center_log "${RED}Total forbidden functions found: $FORBIDDEN_COUNT${NC}"
    center_log "${RED}RESULT: FAILURE${NC}"
else
    center_log "${GREEN}RESULT: PERFECT${NC}"
fi
[ "$SHOW_TIME" = true ] && center_log "${BLUE}Execution time:${NC} ${CYAN}${DURATION}s${NC}"
[ $total_errors -ne 0 ] && safe_exit 1
safe_exit 0
