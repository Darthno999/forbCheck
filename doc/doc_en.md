# COMPLETE DOCUMENTATION - ForbCheck (forb.sh)

**Version:** 1.16.0
**Author:** Mrdolls
**Update Date:** 2026-04-10
**Repository:** https://github.com/Mrdolls/forbCheck

---

## 📖 Table of Contents

1. [General Overview](#general-overview)
2. [Installation & Configuration](#installation--configuration)
3. [General Syntax](#general-syntax)
4. [Flags & Options](#flags--options)
5. [Default Behaviors](#default-behaviors)
6. [Execution Modes](#execution-modes)
7. [Presets](#presets)
8. [Advanced Use Cases](#advanced-use-cases)
9. [Error Handling](#error-handling)
10. [Practical Examples](#practical-examples)

---

## General Overview

**ForbCheck** is a static and dynamic analysis tool designed to detect the use of forbidden or unauthorized functions in C/C++ projects. The tool can analyze:

- **Compiled binaries**: Via symbol extraction with `nm`
- **Source files**: Via pattern searching in `.c` files
- **Linked libraries**: Automatic detection of dependencies

### Fundamental Principle

ForbCheck operates based on **function lists** stored in **presets** (`.preset` files). Each preset defines a set of rules for a given project.

**Default Mode (Whitelist)**: Listed functions are **authorized**.
**Blacklist Mode**: Listed functions are **forbidden** (logic inversion).

---

## Installation & Configuration

### Key Directories

| Directory | Path | Description |
|-----------|--------|-------------|
| Installation | `~/.forb/` | Root directory (created automatically) |
| Library | `~/.forb/lib/` | Internal modules (Shell & Perl) forming the core |
| Presets | `~/.forb/presets/` | Storage for `.preset` files |
| Logs | `~/.forb/logs/` | Log files generated with `--log` |
| HTML Reports | `~/.forb/reports_html/` | HTML files generated with `--html` |

### Required Dependencies

The tool requires the following commands to function:

| Command | Utility |
|----------|---------|
| `nm` | Extracting symbols from binaries |
| `perl` | Data processing and analysis |
| `curl` | Downloading presets |
| `tar` | Extracting archives |
| `bc` (optional) | Calculating execution time (`-t`) |

If a dependency is missing, ForbCheck will display an error and exit with code 1.

---

## General Syntax

```bash
./forb.sh [OPTIONS] [TARGET] [-f FILES...]
```

### Components

- **OPTIONS**: Control flags (flexible order, see FLAGS section)
- **TARGET**: Path to the binary or source directory to analyze (optional if `-s` or `--no-auto`)
- **-f FILES...**: List of specific files/symbols to analyze (after the `-f` flag)

### Key Syntax Points

1. **Option order is flexible**: `forb -s -v <target>` = `forb -v -s <target>`
2. **Short flags can be combined**: `forb -svpa <target>` = `forb -s -v -p -a <target>`
3. **Long flags do not combine**: `--preset --scan-source` (use short forms)
4. **TARGET must be distinct from -f**: TARGET identifies the project, -f specifies files to scan
5. **-f must be followed by files**: `forb <target> -f file1.c file2.c` (the flag consumes all subsequent arguments until the next flag)

---

## Flags & Options

### 📌 HELP & INFORMATION OPTIONS

#### `-h` / `--help`

**Syntax:**
```bash
./forb.sh -h
./forb.sh --help
```

**Description:** Displays the complete help menu with a list of all available flags and their descriptions.

**Behavior:**
- Displays formatted text with all available options
- Exits immediately after display (exit code 0)
- Does not require a target

**Example:**
```bash
./forb.sh --help
```

---

#### `--version`

**Syntax:**
```bash
./forb.sh --version
```

**Description:** Displays the ForbCheck version number.

**Behavior:**
- Displays the version in `V1.14.5` format
- Exits immediately (exit code 0)
- Does not require a target

**Example:**
```bash
./forb.sh --version
# Output: V1.16.0
```

---

### 📊 OUTPUT & LOGGING OPTIONS

#### `--json`

**Syntax:**
```bash
./forb.sh --json [OPTIONS] <target>
```

**Description:** Switches the output to JSON format instead of colored text.

**Behavior:**
- All colored text output is suppressed
- Complete output is in valid JSON format
- Scan information is included in the JSON
- The `--log` flag is ignored in JSON mode (no text log file)
- Displays a structured JSON object at the end of the scan

**JSON Output (structure):**
```json
{
  "target": "<binary_path>",
  "version": "1.16.0",
  "forbidden_count": 5,
  "mode": "whitelist",
  "results": [
    {
      "function": "strcpy",
      "locations": [
        { "file": "main.c", "line": 42 },
        { "file": "utils.c", "line": 10 }
      ]
    }
  ],
  "status": "FAILURE"
}
```

**Special Case:**
- If no forbidden functions are found, `status` = `"PERFECT"` and `forbidden_count` = 0
- In source mode (`-s`), locations include the exact line number

**Example:**
```bash
./forb.sh --json ./my_binary | jq '.forbidden_count'
```

---

#### `--html`

**Syntax:**
```bash
./forb.sh --html [OPTIONS] <target>
```

**Description:** Exports results as an interactive web report (with advanced UI) instead of the usual terminal output.

**Behavior:**
- Terminal standard interface is silenced (hidden).
- Creates a styled report file (modern, dynamic) in `~/.forb/reports_html/`.
- Displays only the absolute path to the newly created file.
- Respects system exit codes (Exit 1 for errors, 0 for *Perfect*).

**Example:**
```bash
./forb.sh -s -np --html
# Output: ℹ HTML report successfully generated in: /home/user/.forb/reports_html/forb_report_2026-04-06_21h10.html
```

---

#### `-oh` or `--open-html`

**Syntax:**
```bash
./forb.sh -oh
```

**Description:** Instantly opens the folder containing all HTML reports using the system's native file explorer.

**Behavior:**
- Uses the universal GUI command (`xdg-open`, macOS `open`, or Windows-Linux `explorer.exe`).
- Exits immediately after opening the window.

**Example:**
```bash
./forb.sh -oh
```

---

#### `-ol` or `--open-logs`

**Syntax:**
```bash
./forb.sh -ol
```

**Description:** Instantly opens the folder containing log files generated via `--log`.

**Behavior:**
- Uses the universal GUI command (`xdg-open`, macOS `open`, or `explorer.exe`).
- Exits immediately after opening the folder.

**Example:**
```bash
./forb.sh -ol
```

---

#### `--log`

**Syntax:**
```bash
./forb.sh --log [OPTIONS] <target>
```

**Description:** Enables log saving to a file.

**Behavior:**
- Creates a log file in `~/.forb/logs/`
- Name format: `l<N>_YYYY-MM-DD_HHhMM.log` (where N is a counter)
- Each scan generates a new numbered file
- Displays the created log file path at the end of the scan
- All text messages (without ANSI colors) are written to the file
- **Compatible with other flags**

**Interaction with `--json`:**
- If `--json` is used with `--log`, JSON is displayed and no log file is created
- Log saving only applies in text mode

**Example:**
```bash
./forb.sh --log ./my_binary
# Output: ℹ Scan log saved to: /home/user/.forb/logs/l1_2026-04-06_14h32.log
```

**Checking the log:**
```bash
cat ~/.forb/logs/l1_*.log
```

---

#### `-t` / `--time`

**Syntax:**
```bash
./forb.sh -t <target>
./forb.sh --time <target>
```

**Description:** Displays the scan execution time in seconds.

**Behavior:**
- Measures time from the start of the scan to the end
- Displays the duration before the final result (PERFECT or FAILURE)
- Format: decimal seconds (e.g., `1.234`)
- **Depends on `bc`**: If `bc` is not installed, displays `0`

**Implementation:**
- On macOS: uses `perl -MTime::HiRes=time`
- On Linux: uses `date +%s.%N`

**Example:**
```bash
./forb.sh -t ./my_binary
```

---

#### `-A` / `--analyse`

**Syntax:**
```bash
./forb.sh -A
./forb.sh --analyse
```

**Description:** Opens the interactive Project Analysis Dashboard (TUI) for a deep dive into your project structure.

**Dashboard Features:**
- **Premium TUI Interface**: Dynamic Cyan/Green design with intuitive keyboard navigation.
- **Automatic Classification**: Separates internal functions (your sources) from external calls (system/libc).
- **Deep Macro Scan**: Recursive analysis of `#define` to find hidden calls.
- **Smart Macro Filtering**: Horizontal tabs for sorting macros.

**Behavior:**
- Uses **Skeleton Parsing** for flawless signature detection.
- **Zero False Positives**: Internal functions take absolute priority.
- Highly optimized for large C projects (42 style).

**Behavior:**
- Measures time from scan start to finish
- Displays duration before the final result (PERFECT or FAILURE)
- Format: decimal number in seconds (e.g., `1.234`)
- **Requires `bc`**: If `bc` is not installed, displays `0`

---

### 🔍 SOURCE SCAN OPTIONS

#### `-s` / `--scan-source`

**Syntax:**
```bash
./forb.sh -s [OPTIONS] [TARGET]
./forb.sh --scan-source [OPTIONS] [TARGET]
```

**Description:** Forces analysis of C/C++ source files instead of a binary.

**Behavior:**
- Switches mode to source scan
- Searches for `*.c` files in current directory or TARGET
- Uses `grep` to detect function calls in code
- Returns exact line number for each occurrence
- **TARGET is optional**: if absent, scans current directory

**Source mode vs binary mode:**
- **Source**: Detects function calls in code (more sensitive to false positives)
- **Binary**: Detects symbols linked to the binary (more reliable)

**Example:**
```bash
./forb.sh -s                    # Scans sources in current directory
./forb.sh -s /path/to/project   # Scans sources in project
./forb.sh -s -f file1.c file2.c # Scans specific files
```

---

#### `-v` / `--verbose`

**Syntax:**
```bash
./forb.sh -v [OPTIONS] <target>
./forb.sh --verbose [OPTIONS] <target>
```

**Description:** Enables verbose mode to display more details during scan.

**Behavior:**
- Increases amount of information displayed
- Specifically useful in source scan mode (`-s`)
- Shows files being processed
- Shows detailed matches with context

**Example:**
```bash
./forb.sh -s -v              # Verbose source mode
./forb.sh -v ./binary        # Verbose binary mode
```

---

#### `-p` / `--full-path`

**Syntax:**
```bash
./forb.sh -p [OPTIONS] <target>
./forb.sh --full-path [OPTIONS] <target>
```

**Description:** Displays **absolute** paths instead of relative paths.

**Behavior:**
- Converts all paths to absolute paths (starting with `/`)
- Useful for scripting or integration with external tools
- Affects both text and JSON display

**Example:**
```bash
./forb.sh -p -s              # Displays /path/to/file.c instead of ./file.c
```

**Special Case:**
- Relative paths starting with `./` are cleaned automatically even without `-p`

---

#### `-a` / `--all`

**Syntax:**
```bash
./forb.sh -a [OPTIONS] <target>
```

**Description:** Displays **all occurrences** of each forbidden function.

**Behavior:**
- By default, the script may limit displayed results
- With `-a`, displays every line where the function is used
- Increases amount of results
- Particularly useful in source mode

**Example:**
```bash
./forb.sh -a -s              # All occurrences in source mode
./forb.sh -a ./binary        # All occurrences in binary mode
```

---

#### `-f [FILES...]`

**Syntax:**
```bash
./forb.sh <target> -f file1 file2 file3
./forb.sh -s -f lib1.c lib2.c lib3.c
```

**Description:** Limits scan to specific files/symbols.

**Behavior:**
- **IMPORTANT**: The `-f` flag consumes all subsequent arguments until the next flag
- Must be placed **after** TARGET (if it exists)
- In source mode: scans only listed `.c` files
- In binary mode: filters symbols to analyze
- Can be used with or without `-s`

**Critical Points:**
1. `-f` must be the **last flag** (it consumes the rest)
2. Files must be space-separated
3. Regex or patterns are not supported (exact files only)

**Example:**
```bash
./forb.sh -s -f main.c utils.c parser.c
./forb.sh ./binary -f symbol1 symbol2
./forb.sh -s -v -f file1.c file2.c
```

---

### 🎯 BLACKLIST/WHITELIST MODE OPTIONS

#### `-b` / `--blacklist`

**Syntax:**
```bash
./forb.sh -b [OPTIONS] <target>
./forb.sh --blacklist [OPTIONS] <target>
```

**Description:** Enables **blacklist mode** (logical inversion).

**Default Behavior (Whitelist):**
- Functions **listed in preset** are **authorized**
- Results show usage of **non-listed** functions
- Logic: "Only these functions are OK"

**Blacklist Mode Behavior (-b):**
- Functions **listed in preset** are **forbidden**
- Results show violations (usage of forbidden functions)
- Logic: "Any function not in the list is OK"

**Example:**
```bash
# Whitelist (Default): Preset contains "printf malloc" (only authorized ones)
./forb.sh ./binary
# Shows violations for any other function (e.g., strcpy found...)

# Blacklist (-b): Preset contains "system execve" (forbidden functions)
./forb.sh -b ./binary
# Shows a violation ONLY if system or execve are found
```

**Marking blacklist mode in preset:**
In the `.preset` file, add the following line for the preset to automatically activate blacklist mode:
```
BLACKLIST_MODE
```

---

### 📋 LIST & VERIFICATION OPTIONS

#### `-l` / `--list`

**Syntax:**
```bash
./forb.sh -l [TARGET] [FUNC1 FUNC2 ...]
./forb.sh --list [TARGET] [FUNC1 FUNC2 ...]
```

**Description:** Displays the loaded preset function list **without performing a scan**.

**Behavior:**
- Loads appropriate preset
- Displays all functions or just requested ones
- Does not scan binary or source
- Exits after display

**Variants:**

1. **Display full list:**
```bash
./forb.sh -l <target>
# Output:
# Listed functions (Whitelist):
# strcpy   strcat   gets     ...
```

2. **Verify specific functions:**
```bash
./forb.sh -l <target> strcpy printf strlen
# Output:
# [OK] -> strcpy (in list)
# [KO] -> printf (not in list)
# [OK] -> strlen (in list)
```

**With blacklist mode:**
```bash
./forb.sh -l -b <target> strcpy printf
# Output:
# [KO] -> strcpy (Blacklisted - not allowed)
# [OK] -> printf (Allowed)
```

---

### 🎛️ PRESET OPTIONS

#### `--preset` / `-P`

**Syntax:**
```bash
./forb.sh --preset <target>
./forb.sh -P <target>
```

**Description:** Forces **interactive** preset selection.

**Behavior:**
- Displays a numbered menu with all available presets
- Waits for user input (number)
- Loads selected preset
- Can be used alone or with other options

**Example:**
```bash
./forb.sh -P ./my_binary
# Output:
# Select a project preset:
# 1) default
# 2) minishell
# 3) so_long
# Enter the number of your preset:
```

**Error Case:**
- If environment is non-interactive, displays error
- If no selection is made, exits with code 1

---

#### `-np` / `--no-preset`

**Syntax:**
```bash
./forb.sh -np <target>
./forb.sh --no-preset <target>
```

**Description:** **Disables** presets and uses an empty list.

**Behavior:**
- Completely ignores preset files
- Uses `default` preset which is empty
- Useful for checking no forbidden functions are used (trivial)
- No functions listed as forbidden

**Example:**
```bash
./forb.sh -np ./my_binary
# Output: RESULT: PERFECT (as no functions are forbidden)
```

---

#### `-lp` / `--list-presets`

**Syntax:**
```bash
./forb.sh -lp
./forb.sh --list-presets
```

**Description:** Displays a list of all available presets.

**Behavior:**
- Scans `~/.forb/presets/` directory
- Displays preset names (without `.preset` extension)
- Exits immediately after (exit code 0)
- Does not require a target

**Example:**
```bash
./forb.sh -lp
# Output:
# Available presets: default, minishell, so_long, ft_printf, libft
```

---

#### `-cp` / `--create-presets`

**Syntax:**
```bash
./forb.sh -cp
./forb.sh --create-presets
```

**Description:** Launches interactive **creation** process for a new preset.

**Behavior:**
- Asks for preset name (replaces spaces with hyphens)
- Creates `.preset` file with a template
- Automatically opens editor to edit the file
- Saves and exits

**Editor used (in this order):**
1. VS Code (`code`)
2. Vim (`vim`)
3. Nano (`nano`)

**Example:**
```bash
./forb.sh -cp
# Output:
# Enter the name of the new preset (e.g., minishell): my_project
# Creating new preset 'my_project'...
# [Editor opens with template]
# [✔] Preset 'my_project' saved!
```

**Generated Template:**
```
# ==============================================================================
# ForbCheck Preset: my_project
# ==============================================================================
#
# AVAILABLE FLAGS (Add them anywhere in this file to activate):
# BLACKLIST_MODE : Inverts the logic...
# ALL_MLX     : Automatically ignores MiniLibX...
# ALL_MATH    : Automatically authorizes math.h functions...
#
# Add your functions below (one per line or space/comma separated):
```

---

#### `-gp` / `--get-presets`

**Syntax:**
```bash
./forb.sh -gp
./forb.sh --get-presets
```

**Description:** **Downloads** default presets from GitHub repository.

**Behavior:**
- Downloads from: `https://github.com/Mrdolls/forbCheck`
- Asks for confirmation before overwriting existing presets
- Adds new presets (doesn't delete existing ones)
- Uses `curl` and `tar`

**Modes:**

1. **Manual Mode (from CLI):**
```bash
./forb.sh -gp
# Output:
# Warning: This will download default presets...
# Continue? (y/n): y
# Downloading presets...
# [✔] Default presets successfully restored!
```

2. **Automatic Mode (during update):**
- During update (`-up`), missing presets are downloaded silently
- Existing presets are never overwritten

---

#### `-op` / `--open-presets`

**Syntax:**
```bash
./forb.sh -op
./forb.sh --open-presets
```

**Description:** Opens the presets directory in the **file explorer**.

**Behavior:**
- Detects operating system
- Opens `~/.forb/presets/` folder with native explorer
- Exits immediately after

**File managers used (by OS):**
- **Windows**: `explorer.exe`
- **Linux**: `xdg-open`
- **macOS**: `open`

**Example:**
```bash
./forb.sh -op
# Opens presets folder in Finder (macOS) or Explorer (Windows)
```

---

#### `-rp` / `--remove-preset`

**Syntax:**
```bash
./forb.sh -rp
./forb.sh --remove-preset
```

**Description:** **Deletes** an existing preset.

**Behavior:**
- Displays list of available presets
- Asks for name of preset to delete
- Asks for confirmation before deletion
- Exits after

**Protections:**
- `default` preset cannot be deleted
- Confirmation requested before each deletion

**Example:**
```bash
./forb.sh -rp
# Output:
# Available presets: default, minishell, so_long
# Enter the name of the preset to remove: minishell
# Are you sure you want to delete 'minishell'? (y/n): y
# [✔] Preset 'minishell' has been removed.
```

---

#### `-e`

**Syntax:**
```bash
./forb.sh -e [TARGET]
```

**Description:** **Edits** manual function list (active preset).

**Behavior:**
- Opens editor for currently loaded preset
- Creates file if missing
- Uses same editor as `-cp` (code > vim > nano)
- Exits after editing

**Example:**
```bash
./forb.sh -e
# Asks which preset to open and opens it in editor for editing
```

---

### 🔧 BINARY & ARCHITECTURE OPTIONS

#### `-mlx`

**Syntax:**
```bash
./forb.sh -mlx <target>
```

**Description:** Enables **MiniLibX mode** (filters internal MLX symbols).

**Behavior:**
- Automatically filters MiniLibX symbols (`mlx_*`)
- Useful for 42 projects using MiniLibX
- Avoids false positives on MLX functions
- Can be combined with `-lm`

**Auto-detection:**
ForbCheck automatically detects MiniLibX if:
- A `*mlx*` or `*minilibx*` folder exists in project
- Binary contains `mlx_*` symbols

**Disable auto-detection:**
```bash
./forb.sh --no-auto -mlx <target>  # Forces MLX mode
./forb.sh --no-auto ./binary        # Scans without auto-detection
```

---

#### `-lm`

**Syntax:**
```bash
./forb.sh -lm <target>
```

**Description:** Enables **Math library** analysis (`libm`).

**Behavior:**
- Authorizes (or filters) math functions (`sin`, `cos`, `sqrt`, etc.)
- Auto-detects if Makefile includes `-lm`
- Auto-detects math symbols in binary
- Can be combined with `-mlx`

**Affected Functions:**
```
sin, cos, tan, asin, acos, atan, atan2,
sinh, cosh, tanh,
exp, log, log10, sqrt, pow, fabs,
floor, ceil, round, trunc
```

---

### 🔄 MAINTENANCE OPTIONS

#### `-t` / `--time`

**Syntax:**
```bash
./forb.sh -t <target>
```

**Description:** Displays scan execution duration.

---

#### `-up` / `--update`

**Syntax:**
```bash
./forb.sh -up
./forb.sh --update
```

**Description:** **Updates** ForbCheck script to the latest version.

**Behavior:**
- Downloads latest version from GitHub
- Compares local version with repository version
- Asks for confirmation before update
- Downloads from: `https://raw.githubusercontent.com/Mrdolls/forb/main/forb.sh`
- Automatically adds missing new presets

**Example:**
```bash
./forb.sh --update
# Output:
# Checking for updates...
# New version available: v1.14.5 (Current: v1.12.0)
# Update? (y/n): y
# [✔] Update successful!
```

---

#### `--remove`

**Syntax:**
```bash
./forb.sh --remove
```

**Description:** Completely **uninstalls** ForbCheck.

**Behavior:**
- Deletes `~/.forb/` directory
- Deletes `forb` shell alias
- Deletes autocompletion configurations
- Cleans `.bashrc` and `.zshrc`
- Asks for confirmation before removal

---

### ⚙️ GLOBAL CONTROL OPTIONS

#### `--no-auto`

**Syntax:**
```bash
./forb.sh --no-auto [OPTIONS] <target>
./forb.sh --no-auto -s
```

**Description:** **Disables** automatic detections.

**Disabled auto-detections:**
1. **Binary auto-detection**: Doesn't search for binary via Makefile
2. **Preset auto-detection**: Doesn't try to match target to preset
3. **Library auto-detection**: Doesn't automatically enable `-mlx` or `-lm`
4. **Source fallback**: If binary not found, doesn't switch to source scan

---

## Default Behaviors

### Default Scan

When running:
```bash
./forb.sh <target>
```

The tool executes this sequence:

1. **Target Verification**:
   - If existing binary file → binary scan
   - If not a file → fallback to source scan
   - If no target: auto-detection + preset prompt

2. **Auto-detection**:
   - Searches for binary via Makefile (`NAME=`)
   - Detects MiniLibX (`mlx_*` symbols or folder)
   - Detects libmath (`-lm` in Makefile or symbols)

3. **Preset Loading**:
   - Searches for exact match: `<target_name>.preset`
   - Searches for partial match: preset containing target name
   - Interactive selection prompt if ambiguous
   - Fallback to `default.preset`

4. **Scan Execution**:
   - Loads preset function list
   - Scans binary or sources
   - Displays results

5. **Exit**:
   - Exit code 0: No violations (PERFECT)
   - Exit code 1: At least one violation (FAILURE)

---

## Execution Modes

### Mode 1: Standard Binary Scan

```bash
./forb.sh ./my_binary
```

**Workflow:**
1. Loads the binary
2. Extracts symbols using `nm`
3. Compares with the preset list
4. Displays violations

---

### Mode 2: Explicit Source Scan

```bash
./forb.sh -s
```

**Workflow:**
1. Searches for `*.c` files in the current directory
2. Uses `grep` to find function calls
3. Compares with the preset list
4. Displays violations with line numbers

---

### Mode 3: List Verification

```bash
./forb.sh -l <target>
```

**Workflow:**
1. Loads the target's preset
2. Displays the list
3. Exits without scanning

---

### Mode 4: Editing and Management

```bash
./forb.sh -e
./forb.sh -cp
./forb.sh -rp
```

**Workflow:**
1. Manages presets interactively
2. Exits after editing

---

## Presets

### Preset structure

```
# ==============================================================================
# ForbCheck Preset: my_project
# ==============================================================================
# SPECIAL FLAGS (add anywhere):
# BLACKLIST_MODE : Inverts logic (only listed functions are authorized)
# ALL_MLX        : Automatically filters mlx_* symbols
# ALL_MATH       : Automatically authorizes math functions
#
# FUNCTIONS (one per line or separated by spaces/commas):

strcpy strcat gets sprintf printf
free malloc calloc realloc
strlen strncpy memcpy memmove
```

### Preset flags

These flags can be added **anywhere** within a `.preset` file:

#### `BLACKLIST_MODE`
- Activates blacklist mode for this preset
- Listed functions become **authorized** (logical inversion)

#### `ALL_MLX`
- Automatically filters MiniLibX symbols (`mlx_*`)
- Equivalent to using `-mlx` for this preset

#### `ALL_MATH`
- Automatically authorizes mathematical functions
- Equivalent to using `-lm` for this preset

---

## Advanced Use Cases

### CI/CD Integration

```bash
./forb.sh --json --no-auto ./build/my_binary | jq '.status'
# Output: "PERFECT" or "FAILURE"
```

### Log Archiving

```bash
./forb.sh --log ./binary && \
  tar czf logs_$(date +%Y%m%d).tar.gz ~/.forb/logs/
```

### Multi-file Scan

```bash
./forb.sh -s -f main.c parser.c lexer.c -v
```

### Comparative Analysis (whitelist vs blacklist)

```bash
echo "=== Whitelist mode ==="
./forb.sh ./binary

echo "=== Blacklist mode ==="
./forb.sh -b ./binary
```

---

## Error Handling

### Exit Codes

| Code | Meaning |
|------|---------------|
| 0 | Success (PERFECT or administrative action) |
| 1 | Error (FAILURE, missing deps, invalid target) |

---

### Common Error Messages

#### "Required command 'nm' is not installed."
**Cause**: `nm` is not available.
**Solution**: Install binutils: `sudo apt install binutils` (Linux) or Xcode (macOS).

#### "Error: No target specified and auto-detection is disabled (--no-auto)."
**Cause**: `--no-auto` requires an explicit target.
**Solution**: `./forb.sh --no-auto <binary>` or `./forb.sh --no-auto -s`.

#### "Non-interactive environment detected."
**Cause**: No interactive terminal (SSH, CI/CD).
**Solution**: Use `-P <preset_name>` or `--json`.

#### "No preset found for 'project_name'."
**Cause**: The preset does not exist.
**Solution**: `./forb.sh -lp` to list, `-cp` to create.

#### "Warning: Using 'default' preset, but it is currently empty."
**Cause**: The `default` preset is empty.
**Solution**: `./forb.sh -e` to add functions.

---

## Practical Examples

### Example 1: Check a 42 Project

```bash
cd ~/project/
./forb.sh
# Binary auto-detection via Makefile
# Preset auto-detection
# MiniLibX auto-detection
# Displays violations
```

### Example 2: Source scan with details

```bash
./forb.sh -s -v -p -a
# Source mode, verbose, full paths, all occurrences
```

### Example 3: JSON export for scripting

```bash
result=$(./forb.sh --json ./binary)
forbidden_count=$(echo "$result" | jq '.forbidden_count')
if [ "$forbidden_count" -gt 0 ]; then
    echo "Found $forbidden_count violations!"
fi
```

### Example 4: Audit with archived log

```bash
./forb.sh --log ./binary && \
  echo "Log saved to $HOME/.forb/logs/"
```

### Example 5: Create and test a preset

```bash
./forb.sh -cp                    # Creates "my_project"
./forb.sh ./binary               # Tests with new preset
./forb.sh -e                     # Edits if necessary
```

### Example 6: Blacklist to forbid specifically

```bash
# Create a preset with blacklist mode
./forb.sh -cp
# Add: BLACKLIST_MODE
# List: system execve fork

# Then test:
./forb.sh ./binary
# Will display ONLY usage of system, execve, and fork (everything else is allowed)
```

---

## Additional Notes

### Performance

- **Binary scan**: Very fast (a few milliseconds)
- **Source scan**: Slower depending on project size (seconds)
- Use `-t` to measure

### Known Limitations

1. **Source false positives**: Comments are only partially filtered
2. **Unlinked symbols**: Symbols may be listed without being used
3. **Complex macros**: Now widely supported (##, variadic), but extreme obfuscation cases may vary
4. **Inline functions**: May not appear as symbols in binary

### Best Practices

1. **Use presets**: Organize by project
2. **Test regularly**: Integrate in CI/CD
3. **Document exceptions**: Note why certain functions are used
4. **Archive logs**: For auditing

---

## Resources

- **GitHub Repository**: https://github.com/Mrdolls/forbCheck
- **Issues & Support**: https://github.com/Mrdolls/forbCheck/issues

---

**End of Documentation**

*This documentation is complete for ForbCheck version 1.14.5. Future versions may introduce changes.*
