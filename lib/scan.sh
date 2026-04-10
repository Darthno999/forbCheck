#!/bin/bash

# ==============================================================================
#  FORBCHECK SCAN MODULE (Analysis & Detection Engine)
# ==============================================================================

auto_detect_libraries() {
    [ "$DISABLE_AUTO" = true ] && return
    [ "$USE_MLX" = true ] && return

    if find . -maxdepth 5 -type d \( -name "*mlx*" -o -name "*minilibx*" \) -print -quit | grep -q . || [ -f "libmlx.a" ] || \
        nm "$TARGET" 2>/dev/null | grep -qiE "mlx_"; then
        USE_MLX=true
        log_info "${CYAN}[Auto-Detect] MiniLibX detected (Use --no-auto to scan everything)${NC}"
    fi

    if [ "$USE_MATH" = false ] && [ -n "$TARGET" ]; then
        if grep -qE "\-lm\b" Makefile 2>/dev/null || \
           nm -u "$TARGET" 2>/dev/null | grep -qE "\b(sin|cos|sqrt|pow|exp|atan2)f?\b"; then
            USE_MATH=true
            log_info "${CYAN}[Auto-Detect] Math library detected (Use --no-auto to scan everything)${NC}"
        fi
    fi
}

auto_detect_target() {
    local make_target fallback_targets fallback_target
    if [ -f "Makefile" ]; then
        make_target=$(grep -m 1 -E "^NAME[[:space:]]*=" Makefile | cut -d '=' -f2 | tr -d ' ' | tr -d '"' | tr -d "'")
        if [ -n "$make_target" ] && [ -f "$make_target" ] && nm "$make_target" &>/dev/null; then
            export AUTO_BIN_DETECTED=true; TARGET="$make_target"
            log_info "${CYAN}[Auto-Detect] Binary : ${BOLD}$TARGET${NC} (via Makefile)"; return 0
        fi
    fi
    if [ "$IS_MAC" = true ]; then fallback_targets=$(find . -maxdepth 1 -type f ! -name "*.sh" ! -name ".*" -exec test -x {} \; -print | sort | sed 's|^\./||')
    else fallback_targets=$(find . -maxdepth 1 -type f -executable ! -name "*.sh" ! -name ".*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2 | sed 's|^\./||')
    fi
    for fallback_target in $fallback_targets; do
        if [ -n "$fallback_target" ] && [ -f "$fallback_target" ] && nm "$fallback_target" &>/dev/null; then
            export AUTO_BIN_DETECTED=true; TARGET="$fallback_target"
            log_info "${CYAN}[Auto-Detect] Binary : ${BOLD}$TARGET${NC} (via file search)"; return 0
        fi
    done
    return 1
}

get_user_defined_funcs() {
    local files=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" -o -name "*.h" \))
    [ -z "$files" ] && return
    echo "$files" | tr '\n' '\0' | xargs -0 perl -e '
        my %shield; local $/ = undef;
        my $types = qr/(?:int|char|float|double|long|short|unsigned|signed|void|size_t|ssize_t|pid_t|sig_atomic_t|bool|t_\w+|struct\s+\w+|enum\s+\w+|FILE|DIR)/;
        foreach my $file (@ARGV) {
            open(my $fh, "<", $file) or next; my $content = <$fh>; close($fh);
            $content =~ s/\/\*.*?\*\//\n/gs; $content =~ s/\/\/.*//g;
            $content =~ s/"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27/ /gs;
            my $skeleton = $content; while ($skeleton =~ s/\{[^{}]*\}/;\n/g) {}
            foreach my $line (split /\n/, $skeleton) {
                next if $line =~ /^\s*$/;
                if ($line =~ /^(.*?)(\b[a-zA-Z_]\w*\b)(\s*\(.*)$/) {
                    my ($avant, $mot) = ($1, $2);
                    if ($avant =~ /^[\s\w\*]+$/ && $avant =~ /\b(?:$types|static|extern)\b|\*/) { $shield{$mot} = 1; }
                }
            }
        }
        my $kw = qr/^(if|while|for|return|else|switch|case|default|do|sizeof)$/;
        foreach my $k (sort keys %shield) { print "$k " unless $k =~ $kw; }
    ' 2>/dev/null
}

scan_source_engine() {
    local files="$1"
    local user_funcs="$2"

    export USE_JSON USE_HTML USE_GRAPH BLACKLIST_MODE VERBOSE SHOW_ALL
    export USER_FUNCS="$user_funcs"
    
    if [ "$BLACKLIST_MODE" = true ]; then
        export BLACKLIST_FUNCS=$(echo "$AUTH_FUNCS" | tr '\n' ' ')
    else
        local keywords="if while for return sizeof switch else case default do static const volatile struct union enum typedef extern inline unsigned signed short long int char float double void bool va_arg va_start va_end va_list NULL del f"
        local macros="WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG S_ISDIR S_ISREG"
        export KEYWORDS_MACROS="$keywords $macros"
        export ALLOW_MLX=0
        [ "$USE_MLX" = true ] && export ALLOW_MLX=1
        export WHITELIST="$(echo "$AUTH_FUNCS" | tr '\n' ' ')"
    fi

    # Run standalone source scan engine (parallelized)
    local cores=$(get_core_count)
    export NO_SUMMARY=true
    echo "$files" | tr '\n' '\0' | xargs -0 -P "$cores" -n 25 perl "$INSTALL_DIR/lib/source_scan.pl"
    unset NO_SUMMARY
    
    # Run standalone macro engine
    local list=$(get_preset_list "$SELECTED_PRESET")
    local cores=$(get_core_count)
    local scan_output=$(echo "$files" | xargs -P "$cores" -I {} perl "$INSTALL_DIR/lib/macro_engine.pl" "{}" "$list" "$BLACKLIST_MODE" "$USE_JSON" "$VERBOSE" "$USER_FUNCS" "$KEYWORDS_MACROS")
    
    if [ -n "$scan_output" ]; then
        log_info "   [${BLUE}Macro Expansion${NC}] -> Scanning for hidden calls..."
        while IFS= read -r line; do log_info "$line"; done <<< "$scan_output"
    fi
}

source_scan() {
    resolve_preset "source"
    load_preset "$SELECTED_PRESET"

    local _src_start=$(get_timestamp)
    
    local files_list=""
    if [ -n "$SPECIFIC_FILES" ]; then
        for f in $SPECIFIC_FILES; do [ -f "$f" ] && files_list+="$f"$'\n'; done
        files_list=$(echo "$files_list" | sed '/^$/d')
    else
        files_list=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" \))
    fi
    if [ -z "$files_list" ]; then
        log_info "${YELLOW}[Warning] No source files (*.c, *.cpp) found in this directory.${NC}"
        safe_exit 0
    fi
    local nb_files=$(echo "$files_list" | grep -c '^')
    if [ "$nb_files" -eq 0 ]; then
        log_info "${YELLOW}[Warning] No source files (*.c, *.cpp) found in this directory.${NC}"
        safe_exit 0
    fi

    parse_preset_flags "$(cat "$ACTIVE_PRESET" 2>/dev/null)"
    local p_mode="Whitelist"; [ "$BLACKLIST_MODE" = true ] && p_mode="Blacklist"

    log_info "${BLUE}Scan Mode  :${NC} ${YELLOW}Source${NC} (*.c / *.cpp)"
    log_info "${BLUE}Preset     :${NC} ${BOLD}${SELECTED_PRESET}${NC} ${CYAN}(${p_mode})${NC}"
    [ -n "$SPECIFIC_FILES" ] && log_info "${BLUE}Scope      :${NC} $SPECIFIC_FILES"
    log_info "\n${BLUE}${BOLD}Execution:${NC}\n-------------------------------------------------"
    log_info "${BLUE}Scanning $nb_files source file(s)...${NC}\n"

    local my_funcs=$(get_user_defined_funcs)
    local scan_output=$(scan_source_engine "$files_list" "$my_funcs")

    if [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ] || [ "$USE_GRAPH" = true ]; then
        export JSON_RAW_DATA="$scan_output" IS_SOURCE_SCAN=true
        if [ "$USE_JSON" = true ]; then
            generate_json_output
        elif [ "$USE_HTML" = true ]; then
            generate_html_report
        else
            generate_callgraph_report
        fi
    else
        while IFS= read -r line; do log_info "$line"; done <<< "$scan_output"
        
        log_info "\n-------------------------------------------------"
        local f_count=$(echo "$scan_output" | grep -c "FORBIDDEN")
        if [ "$f_count" -eq 0 ]; then
            center_log "${GREEN}RESULT: PERFECT${NC}"
        else
            center_log "${RED}Total forbidden functions found: $f_count${NC}"
            center_log "${RED}RESULT: FAILURE${NC}"
        fi

        if [ "$SHOW_TIME" = true ]; then
            local _dur=$(calculate_duration "$_src_start" "$(get_timestamp)")
            center_log "${BLUE}Execution time:${NC} ${CYAN}${_dur}s${NC}"
        fi
        log_info "\n${GREEN}Source audit complete.${NC}"
    fi
    safe_exit 0
}

extract_undefined_symbols() {
    local cores=$(get_core_count)
    if [ "$IS_MAC" = true ]; then
        raw_funcs=$(nm -u "$TARGET" 2>/dev/null | awk '{print $NF}' | sed -E 's/^_//;s/@.*//' | sort -u)
        NM_RAW_DATA=$(find . -not -path '*/.*' -type f \( -name "*.o" -o -name "*.a" \) ! -name "$TARGET" ! -path "*mlx*" ! -path "*MLX*" -print0 2>/dev/null | xargs -0 -P"$cores" nm -o 2>/dev/null)
        MY_DEFINED=$(grep -E ' [TRD] ' <<< "$NM_RAW_DATA" | awk '{print $NF}' | sed -E 's/^_//' | sort -u)
        ALL_UNDEFINED=$(grep " U " <<< "$NM_RAW_DATA" | sed -E 's/ U _/ U /')
    else
        raw_funcs=$(nm -u "$TARGET" 2>/dev/null | awk '{print $NF}' | sed -E 's/@.*//' | sort -u)
        NM_RAW_DATA=$(find . -not -path '*/.*' -type f \( -name "*.o" -o -name "*.a" \) ! -name "$TARGET" ! -path "*mlx*" ! -path "*MLX*" -print0 2>/dev/null | xargs -0 -P"$cores" nm -A 2>/dev/null)
        MY_DEFINED=$(grep -E ' [TRD] ' <<< "$NM_RAW_DATA" | awk '{print $NF}' | sort -u)
        ALL_UNDEFINED=$(grep " U " <<< "$NM_RAW_DATA")
    fi
}

filter_forbidden_functions() {
    local filter_out=$(perl "$INSTALL_DIR/lib/symbol_filter.pl" \
        "$raw_funcs" \
        "$(echo "$AUTH_FUNCS" | tr '\n' ' ')" \
        "$BLACKLIST_MODE" \
        "$USE_MLX" \
        "$USE_MATH" \
        "$MY_DEFINED" \
        "$SHOW_ALL")

    # Display OK messages (stored in filter_out) and extract the forbidden list
    echo "$filter_out" | grep -v "^FORBIDDEN_LIST:"
    forbidden_list=$(echo "$filter_out" | grep "^FORBIDDEN_LIST:" | cut -d: -f2-)
}

print_analysis_report() {
    local f_name spec_locs errors=0
    for f_name in $forbidden_list; do
        spec_locs=$(grep -E ":.*\b${f_name}\b" <<< "$grep_res")
        if [ -n "$spec_locs" ]; then
            log_info "   [${RED}FORBIDDEN${NC}] -> $f_name"
            [ -z "$SPECIFIC_FILES" ] && errors=$((errors + 1))
            while read -r line; do
                [ -z "$line" ] && continue
                local f_path=$(echo "$line" | cut -d: -f1); local l_num=$(echo "$line" | cut -d: -f2)
                local snippet=$(echo "$line" | cut -d: -f3- | sed 's/^[[:space:]]*//')
                if clean_code_snippet "$snippet" "$f_name" >/dev/null; then
                    local d_name=$( [ "$FULL_PATH" = true ] && echo "$f_path" | sed 's|^\./||' || basename "$f_path" )
                    local prefix=$( [ -n "$SPECIFIC_FILES" ] && [ "$VERBOSE" = false ] && echo "line ${l_num}" || echo "${d_name}:${l_num}" )
                    if [ "$VERBOSE" = true ]; then log_info "          ${YELLOW}↳ Location: ${BLUE}${prefix}${NC}: ${CYAN}$(crop_line "$f_name" "$snippet")${NC}"
                    else log_info "          ${YELLOW}↳ Location: ${BLUE}${prefix}${NC}"; fi
                fi
            done <<< "$spec_locs"
        elif [ -z "$SPECIFIC_FILES" ]; then
            log_info "   [${YELLOW}WARNING${NC}]   -> $f_name"
            local objs=$(grep -E " U ${f_name}$" <<< "$ALL_UNDEFINED" | awk -F: '{split($1, path, "/"); print path[length(path)]}' | sort -u | tr '\n' ' ')
            log_info "          ${YELLOW}↳ Found in objects: ${BLUE}${objs}${NC}"
            [[ "$f_name" =~ ^(strlen|memset|memcpy|printf|puts|putchar)$ ]] && log_info " ${CYAN}(Builtin?)${NC}" || log_info " ${CYAN}(Sync?)${NC}"
        fi
    done
    return $errors
}

build_grep_results() {
    local f_name safe_name; grep_res=""
    for f_name in $forbidden_list; do
        safe_name=$(printf '%s\n' "$f_name" | sed 's/[.[\*^$]/\\&/g')
        local args=("-rHE" "\b${safe_name}\b" ".")
        if [ -n "$SPECIFIC_FILES" ]; then for f in $SPECIFIC_FILES; do args+=("--include=$f"); done
        else args+=("--include=*.c"); fi
        grep_res+="$(grep "${args[@]}" -n 2>/dev/null | grep -vE "mlx|MLX")"$'\n'
    done
}

run_analysis() {
    export IS_SOURCE_SCAN=false
    extract_undefined_symbols; filter_forbidden_functions; build_grep_results
    export FORBIDDEN_COUNT=0; [ -n "$forbidden_list" ] && FORBIDDEN_COUNT=$(echo "$forbidden_list" | wc -w)
    if [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ] || [ "$USE_GRAPH" = true ]; then
        if [ "$USE_JSON" = true ]; then
            generate_json_output "$FORBIDDEN_COUNT"
        elif [ "$USE_HTML" = true ]; then
            generate_html_report "$FORBIDDEN_COUNT"
        else
            generate_callgraph_report
        fi
        [ $FORBIDDEN_COUNT -eq 0 ] && return 0 || return 1
    else
        print_analysis_report; local errs=$?; if [ $errs -eq 0 ] && [ $FORBIDDEN_COUNT -eq 0 ]; then log_info "\t${GREEN}No forbidden functions detected.${NC}"; fi
        return $errs
    fi
}

check_binary_cache() {
    local bin_mt=$(get_file_mtime "$TARGET")
    local latest_src_mt=0
    
    if [ "$IS_MAC" = true ]; then
        latest_src_mt=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" \) -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1)
    else
        latest_src_mt=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" \) -exec stat -c %Y {} + 2>/dev/null | sort -n | tail -1)
    fi
    
    [ -z "$latest_src_mt" ] && latest_src_mt=0
    
    if [ "$latest_src_mt" -gt "$bin_mt" ]; then
        SET_WARNING=true
    else
        SET_WARNING=false
    fi
}
