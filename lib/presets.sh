#!/bin/bash

# ==============================================================================
#  FORBCHECK PRESET MODULE (Preset Management)
# ==============================================================================

get_preset_list() {
    local preset_name="$1"
    local preset_file="$PRESET_DIR/${preset_name}.preset"
    [ ! -f "$preset_file" ] && return 1

    local raw_content=$(grep -vE "^\s*#" "$preset_file")

    if echo "$raw_content" | grep -q "ALL_MATH"; then
        local math_funcs="cos sin tan acos asin atan atan2 cosh sinh tanh exp frexp ldexp log log10 modf pow sqrt ceil fabs floor fmod round trunc abs labs"
        raw_content="$raw_content $math_funcs"
    fi

    echo "$raw_content" | sed -E 's/\b(BLACKLIST_MODE|ALL_MLX|ALL_MATH)\b//g' | \
        tr ',' ' ' | tr -s ' ' '\n' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        grep -v '^$' | tr '\n' ' ' | sed 's/ $//'
}

prompt_preset_menu() {
    [ "$DISABLE_AUTO" == "true" ] && log_info "\n${YELLOW}${BOLD}Auto-detection disabled by --no-auto flag.${NC}"

    if [ ! -f "$PRESET_DIR/default.preset" ]; then
        mkdir -p "$PRESET_DIR"
        touch "$PRESET_DIR/default.preset"
    fi

    local presets=($(ls "$PRESET_DIR" 2>/dev/null | grep '\.preset$' | sed 's/\.preset//'))
    if [ -t 0 ] || [ -c /dev/tty ]; then
        export SELECTED_PRESET=$(perl "$INSTALL_DIR/lib/menu.pl" "${presets[@]}")
        if [ $? -ne 0 ] || [ -z "$SELECTED_PRESET" ]; then
            log_info "${RED}Preset selection aborted.${NC}"
            safe_exit 1
        fi
        log_info "${GREEN}Loaded preset: ${BOLD}$SELECTED_PRESET${NC}"
    else
        log_info "${RED}Error: Non-interactive environment detected. Please explicitly provide a preset.${NC}"
        safe_exit 1
    fi

    [ -z "$SELECTED_PRESET" ] && { log_info "${RED}Error: Preset selection aborted.${NC}"; safe_exit 1; }
}

auto_find_preset() {
    local target_name_lower="$1"
    local preset_file base_name base_name_lower

    for preset_file in "$PRESET_DIR"/*.preset; do
        [ -e "$preset_file" ] || continue
        base_name=$(basename "$preset_file" .preset)
        base_name_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')

        if [[ "$target_name_lower" == *"$base_name_lower"* ]]; then
            export SELECTED_PRESET="$base_name"
            log_info "${CYAN}[Auto-Detect] Preset : ${BOLD}${base_name}${NC}"
            return 0
        fi
    done
    if find . -maxdepth 3 -type f \( -name "*.cpp" -o -name "*.hpp" -o -name "*.cc" \) -print -quit | grep -q "."; then
        if [ -f "$PRESET_DIR/cpp.preset" ]; then
            log_info "${CYAN}[Auto-Detect] Preset : ${BOLD}cpp${NC} (C++ detected)"
            export SELECTED_PRESET="cpp"
            return 0
        fi
    fi
    return 1
}

resolve_preset() {
    local mode="$1"
    local project_name

    if [ "$DISABLE_PRESET" = true ]; then
        export SELECTED_PRESET="default"
        return 0
    fi

    project_name=$([ -n "$TARGET" ] && basename "$TARGET" || basename "$PWD")

    if [ "$USE_PRESET" -eq 1 ]; then
        prompt_preset_menu
        return 0
    fi
    if [ "$DISABLE_AUTO" = "true" ] && { [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ] || [ "$USE_GRAPH" = true ]; }; then
        export SELECTED_PRESET="default"
        return 0
    fi

    if [ -z "$SELECTED_PRESET" ] && [ -n "$project_name" ]; then
        if [ -f "$PRESET_DIR/${project_name}.preset" ]; then
            export SELECTED_PRESET="$project_name"
            [ "$DISABLE_AUTO" != "true" ] && log_info "${CYAN}[Auto-Detect] Preset : ${BOLD}${project_name}${NC} (Exact match)"
            return 0
        fi
    fi

    if [ "$DISABLE_AUTO" != "true" ] && [ -z "$SELECTED_PRESET" ]; then
        auto_find_preset "$(echo "$project_name" | tr '[:upper:]' '[:lower:]')"
    fi
    [ -n "$SELECTED_PRESET" ] && return 0

    if [ "$DO_EDIT_LIST" = true ] || [ "$RUN_LIST" = true ] || [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ] || [ "$USE_GRAPH" = true ]; then
        export SELECTED_PRESET="default"
        return 0
    fi
    prompt_preset_menu
}

load_preset() {
    local target_name="$1"
    ACTIVE_PRESET="$PRESET_DIR/${target_name}.preset"

    if [ "$target_name" = "default" ] && [ ! -f "$ACTIVE_PRESET" ]; then
        touch "$ACTIVE_PRESET"
    fi

    if [ ! -f "$ACTIVE_PRESET" ]; then
        local available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')
        if [ "$USE_JSON" = true ]; then
            log_info "{\"target\":\"$TARGET\",\"version\":\"$VERSION\",\"error\":\"No preset found for '${target_name}'\",\"status\":\"FAILURE\"}"
        else
            log_info "\033[31mError: No preset found for '${target_name}'.\033[0m"
            [ -z "$available_presets" ] && log_info "\033[33mNo presets available.\033[0m" || log_info "Available presets: \033[36m$available_presets\033[0m"
        fi
        safe_exit 1
    fi
}

list_presets() {
    local should_exit="${1:-1}"
    local available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')
    if [ -z "$available_presets" ]; then
        log_info "\033[33mNo presets available in $PRESET_DIR\033[0m"
    else
        log_info "Available presets: \033[36m$available_presets\033[0m"
    fi
    [ "$should_exit" -eq 1 ] && safe_exit 0
}

open_presets() {
    log_info "\033[32mOpening presets directory: $PRESET_DIR\033[0m"
    if command -v explorer.exe > /dev/null; then (cd "$PRESET_DIR" && explorer.exe .)
    elif command -v xdg-open > /dev/null; then xdg-open "$PRESET_DIR"
    elif command -v open > /dev/null; then open "$PRESET_DIR"
    else log_info "\033[31mError: Could not open the folder automatically. Path: $PRESET_DIR\033[0m"
    fi
    safe_exit 0
}

open_html() {
    local html_dir="$INSTALL_DIR/reports_html"
    mkdir -p "$html_dir"
    log_info "\033[32mOpening HTML reports directory: $html_dir\033[0m"
    if command -v explorer.exe > /dev/null; then (cd "$html_dir" && explorer.exe .)
    elif command -v xdg-open > /dev/null; then xdg-open "$html_dir"
    elif command -v open > /dev/null; then open "$html_dir"
    else log_info "\033[31mError: Could not open the folder automatically. Path: $html_dir\033[0m"
    fi
    safe_exit 0
}

open_logs() {
    mkdir -p "$LOG_DIR"
    log_info "\033[32mOpening logs directory: $LOG_DIR\033[0m"
    if command -v explorer.exe > /dev/null; then (cd "$LOG_DIR" && explorer.exe .)
    elif command -v xdg-open > /dev/null; then xdg-open "$LOG_DIR"
    elif command -v open > /dev/null; then open "$LOG_DIR"
    else log_info "\033[31mError: Could not open the folder automatically. Path: $LOG_DIR\033[0m"
    fi
    safe_exit 0
}

parse_preset_flags() {
    local raw_content="$1"
    [ -z "$raw_content" ] && { log_info "${YELLOW}[Warning] Preset is empty.${NC}"; AUTH_FUNCS=""; return; }
    raw_content=$(echo "$raw_content" | sed 's/#.*//g')
    if echo "$raw_content" | grep -q "BLACKLIST_MODE"; then export BLACKLIST_MODE=true; raw_content=$(echo "$raw_content" | sed 's/BLACKLIST_MODE//g'); fi
    if echo "$raw_content" | grep -q "ALL_MLX"; then USE_MLX=true; raw_content=$(echo "$raw_content" | sed 's/ALL_MLX//g'); fi
    if echo "$raw_content" | grep -q "ALL_MATH"; then
        USE_MATH=true
        local math_funcs="cos sin tan acos asin atan atan2 cosh sinh tanh exp frexp ldexp log log10 modf pow sqrt ceil fabs floor fmod round trunc abs labs"
        raw_content=$(echo "$raw_content" | sed 's/ALL_MATH//g')
        raw_content="$raw_content $math_funcs"
    fi
    AUTH_FUNCS=$(echo "$raw_content" | tr ',' ' ' | tr -s ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
    [ -z "$AUTH_FUNCS" ] && [ "$BLACKLIST_MODE" = false ] && log_info "${YELLOW}[Warning] Preset loaded but function list is empty.${NC}"
}
