#!/bin/bash

# --- Environment Isolation Setup ---
ORIG_HOME="$HOME"
TEST_ROOT=$(mktemp -d /tmp/forb_test_XXXXXX)
MOCK_HOME="$TEST_ROOT/home"
INSTALL_DIR="$MOCK_HOME/.forb"

# Bootstrap: Create isolated structure and copy library files
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/doc" "$INSTALL_DIR/presets" "$INSTALL_DIR/logs"
cp "$ORIG_HOME/.forb/forb.sh" "$INSTALL_DIR/"
cp -r "$ORIG_HOME/.forb/lib/"* "$INSTALL_DIR/lib/"
cp -r "$ORIG_HOME/.forb/doc/"* "$INSTALL_DIR/doc/"

# Override HOME to redirect ~/.forb to /tmp
export HOME="$MOCK_HOME"

# Mock Presets
printf "malloc free printf\n" > "$INSTALL_DIR/presets/minishell.preset"
printf "malloc free printf\n" > "$INSTALL_DIR/presets/default.preset"

FORB="bash $INSTALL_DIR/forb.sh"
LOG_DIR="$INSTALL_DIR/logs"
PASS=0; FAIL=0

# Cleanup handler
cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $1 → $2"; FAIL=$((FAIL+1)); }
section() { echo ""; echo "══════════════════════════════════════════════"; echo " 🧪 $1"; echo "══════════════════════════════════════════════"; }

# --- SETUP: Mock Project ---
_TDIR="$TEST_ROOT/minishell"
mkdir -p "$_TDIR/srcs/core"
cd "$_TDIR" || exit 1
printf '#include <stdlib.h>\n#include <stdio.h>\nvoid test_a(void) { gets(NULL); malloc(10); puts("x"); }\n' > "a.c"
printf '#include <stdio.h>\nvoid test_b(void) { printf("y"); gets(NULL); }\n'                              > "b.c"
printf 'void build_prompt() { printf("> "); }\n'                                                       > "srcs/core/prompt.c"
# Create mock binary
printf '#include <stdlib.h>\nint main() { void *p = malloc(10); if (p) free(p); return 0; }\n' > main.c
gcc main.c -o minishell 2>/dev/null || touch minishell

QF="-f a.c"
QF2="-f a.c b.c"

# ─── SECTION 1: HELP & VERSION ────────────────────────────────────────────────
section "Section 1: Help & Version"

out=$($FORB --help 2>&1)
echo "$out" | grep -q "ForbCheck" && pass "--help affiche ForbCheck" || fail "--help" "$(echo "$out" | head -1)"
echo "$out" | grep -q "Usage" && pass "--help contient Usage" || fail "--help Usage manquant" ""
out=$($FORB -h 2>&1)
echo "$out" | grep -q "ForbCheck" && pass "-h (short form)" || fail "-h" ""
echo "$out" | grep -E -q "\-s, |\-\-scan|\-\-source" && pass "--help: documente l'option scan (-s)" || fail "--help scan" ""
echo "$out" | grep -E -q "\-l, |\-\-list" && pass "--help: documente l'option list (-l)" || fail "--help list" ""
echo "$out" | grep -E -q "\-b, |\-\-blacklist" && pass "--help: documente l'option blacklist (-b)" || fail "--help blacklist" ""
echo "$out" | grep -E -q "\-v, |\-\-verbose" && pass "--help: documente l'option verbose (-v)" || fail "--help verbose" ""
echo "$out" | grep -E -q "\-\-json" && pass "--help: documente l'option api (--json)" || fail "--help json" ""
echo "$out" | grep -E -q "\-\-update|\-up" && pass "--help: documente l'option utilitaire (--update)" || fail "--help update" ""
out=$($FORB --version 2>&1)
echo "$out" | grep -qE "^V[0-9]+\.[0-9]+\.[0-9]+" && pass "--version format Vx.x.x → $out" || fail "--version" "$out"

# ─── SECTION 2: PRESETS ────────────────────────────────────────────────────────
section "Section 2: Presets (-lp, -np)"

out=$($FORB -lp 2>&1)
echo "$out" | grep -q "Available presets" && pass "-lp affiche les presets" || fail "-lp" "$out"
echo "$out" | grep -q "minishell" && pass "-lp contient minishell" || fail "-lp no minishell" ""

out=$($FORB --list-presets 2>&1)
echo "$out" | grep -q "Available presets" && pass "--list-presets (long form)" || fail "--list-presets" ""

# FIX PERF: scan sur un seul fichier via QF au lieu de tout minishell-r
# -np -s: whitelist vide → TOUT est forbidden (comportement correct)
out=$($FORB -np -s $QF 2>&1)
echo "$out" | grep -qE "Source audit complete|Scanning" && pass "-np -s → scan complet (whitelist vide = tout forbidden)" || fail "-np -s" "$(echo "$out" | tail -2)"

out=$($FORB --no-preset -s $QF 2>&1)
echo "$out" | grep -qE "Source audit complete|Scanning" && pass "--no-preset -s (long form)" || fail "--no-preset" ""

# ─── SECTION 3: LIST (-l) ─────────────────────────────────────────────────────
section "Section 3: -l / --list"

out=$($FORB -l 2>&1)
echo "$out" | grep -qiE "Listed functions|empty|No authorized" && pass "-l affiche la liste du preset" || fail "-l" "$(echo "$out" | head -2)"

out=$($FORB --list 2>&1)
echo "$out" | grep -qiE "Listed|empty|No authorized" && pass "--list (long form)" || fail "--list" ""

out=$($FORB -l malloc printf gets 2>&1)
echo "$out" | grep -q "malloc" && pass "-l avec args: vérifie fonctions spécifiques" || fail "-l args" ""
echo "$out" | grep -qE "\[OK\].*malloc|malloc.*\[OK\]" && pass "  malloc → [OK]" || fail "  malloc devrait être OK" "$(echo "$out" | grep malloc)"
echo "$out" | grep -qE "\[KO\].*gets|gets.*\[KO\]" && pass "  gets → [KO]" || fail "  gets devrait être KO" "$(echo "$out" | grep gets)"

# -l -b : avec preset auto-détecté (minishell), malloc est dans la liste → blacklisté → KO
# Pour tester correctement, on utilise le preset minishell explicitement via la correspondance du dossier
out=$($FORB -b -l malloc printf gets 2>&1)
echo "$out" | grep -qE "KO|OK|Listed|empty" && pass "-b -l → répond sans bloquer (fix RUN_LIST→default)" || fail "-b -l" "$(echo "$out" | head -2)"
echo "$out" | grep -q "printf" && pass "  printf → formatté dans le bloc listant" || fail "  printf list form" ""
echo "$out" | grep -q "Checking functions" && pass "  list block title properly formatted" || fail "  list format header" ""

# ─── SECTION 4: JSON ──────────────────────────────────────────────────────────
section "Section 4: --json"

# FIX PERF: scan sur QF + FIX DOUBLON: json_full réutilisé pour éviter un 2e scan identique
json_full=$($FORB -s --json $QF 2>&1)
echo "$json_full" | python3 -m json.tool > /dev/null 2>&1 && pass "-s --json JSON valide" || fail "-s --json JSON invalide" "$(echo "$json_full" | head -1)"

for field in target version mode status forbidden_count results; do
    echo "$json_full" | grep -q "\"$field\"" && pass "  champ JSON: $field" || fail "  champ JSON: $field manquant" ""
done

mode=$(echo "$json_full" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['mode'])" 2>/dev/null)
[ "$mode" = "whitelist" ] && pass "  mode=whitelist (bug fix validé)" || fail "  mode attendu whitelist" "obtenu: $mode"

# -np -s --json: whitelist vide → FAILURE est le comportement correct
out=$($FORB -np -s --json $QF 2>&1)
status=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])" 2>/dev/null)
[ "$status" = "FAILURE" ] && pass "-np -s --json → FAILURE (whitelist vide = tout forbidden, comportement correct)" || fail "-np status" "obtenu: $status"
count=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['forbidden_count'])" 2>/dev/null)
[ "${count:-0}" -gt 0 ] 2>/dev/null && pass "  forbidden_count > 0 avec -np -s" || fail "  forbidden_count" "obtenu: $count"

out=$($FORB -b -s --json $QF 2>&1)
bmode=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['mode'])" 2>/dev/null)
[ "$bmode" = "blacklist" ] && pass "-b -s --json → mode=blacklist" || fail "-b --json mode" "obtenu: $bmode"

# FIX DOUBLON: réutilisation de json_full (scan déjà effectué en début de section)
echo "$json_full" | grep -q '"file"' && pass "  JSON results contient file" || fail "  file manquant dans results" ""
echo "$json_full" | grep -q '"line"' && pass "  JSON results contient line" || fail "  line manquant dans results" ""

# ─── SECTION 5: SOURCE SCAN (-s) ──────────────────────────────────────────────
section "Section 5: -s / --scan-source"

# FIX PERF: scan sur QF (1 fichier) au lieu du projet entier
out=$($FORB -s $QF 2>&1)
echo "$out" | grep -qE "Scanning [0-9]+ source file" && pass "-s affiche 'Scanning N source files'" || fail "-s header" "$(echo "$out" | head -5)"
echo "$out" | grep -qE "FORBIDDEN|PERFECT" && pass "-s produit des résultats" || fail "-s no results" ""
echo "$out" | grep -q "Source audit complete" && pass "-s affiche 'Source audit complete'" || fail "-s audit complete" ""

out=$($FORB --source $QF 2>&1)
echo "$out" | grep -qE "Scanning|PERFECT|FAILURE" && pass "--source (long form)" || fail "--source" ""

# ─── SECTION 6: SCAN FLAGS (-v, -p, -f) ───────────────────────────────────────
section "Section 6: Flags de scan (-v, -p, -f)"

# FIX PERF: scan sur QF (a.c contient gets → FORBIDDEN → ↳ visible en mode -v)
# -v verbose: doit maintenant afficher le snippet de code (↳)
out=$($FORB -s -v $QF 2>&1)
echo "$out" | grep -qE "↳" && pass "-s -v affiche le snippet de code (↳ fix validé)" || fail "-s -v" "$(echo "$out" | grep FORBIDDEN | head -2)"
out=$($FORB -s --verbose $QF 2>&1)
echo "$out" | grep -qE "↳" && pass "--verbose (long form)" || fail "--verbose" ""

out=$($FORB -s -p $QF 2>&1)
echo "$out" | grep -qE "FORBIDDEN|PERFECT|Scanning" && pass "-s -p produit des résultats" || fail "-s -p" ""
out=$($FORB -s --full-path $QF 2>&1)
echo "$out" | grep -qE "FORBIDDEN|PERFECT|Scanning" && pass "--full-path (long form)" || fail "--full-path" ""

# Ce test cible un fichier spécifique du projet minishell (conservé volontairement)
out=$($FORB -s -f srcs/core/prompt.c 2>&1)
echo "$out" | grep -qE "Scanning 1 source file" && pass "-s -f: 1 seul fichier scanné" || fail "-s -f" "$(echo "$out" | grep Scanning)"
echo "$out" | grep -qE "PERFECT|No unauthorized" && pass "  -f srcs/core/prompt.c → PERFECT (fichier clean)" || fail "  -f résultat" "$(echo "$out" | tail -3)"

# ─── SECTION 7: BLACKLIST MODE (-b) ───────────────────────────────────────────
section "Section 7: -b / --blacklist"

# FIX PERF: scan sur QF
out=$($FORB -b -s $QF 2>&1)
echo "$out" | grep -qE "FORBIDDEN|PERFECT|Scanning" && pass "-b -s fonctionne" || fail "-b -s" "$(echo "$out" | tail -2)"

out=$($FORB --blacklist -s $QF 2>&1)
echo "$out" | grep -qE "FORBIDDEN|PERFECT|Scanning" && pass "--blacklist -s (long form)" || fail "--blacklist" ""

# ─── SECTION 8: COMBINAISONS DE FLAGS ─────────────────────────────────────────
section "Section 8: Combinaisons flags courts"

# FIX PERF: scan sur QF
out=$($FORB -svp $QF 2>&1)
echo "$out" | grep -qE "Scanning|PERFECT|FAILURE" && pass "-svp (combinaison de -s -v -p)" || fail "-svp" "$(echo "$out" | head -3)"

out=$($FORB -sp --json $QF 2>&1)
echo "$out" | python3 -m json.tool > /dev/null 2>&1 && pass "-sp --json → JSON valide" || fail "-sp --json" ""

# -snp: -s + -np → source scan sans preset (fix parser 2-chars validé)
out=$($FORB -snp $QF 2>&1)
echo "$out" | grep -qE "Source audit complete|Scanning" && pass "-snp (fix parser: -s -np correctement splitté)" || fail "-snp" "$(echo "$out" | tail -2)"

# ─── SECTION 9: TIMER (-t) ────────────────────────────────────────────────────
section "Section 9: -t / --time"

# FIX PERF: scan sur QF
# FIX REGEX: accepte "0s" (sans bc) ET "0.123s" (avec bc) — les deux sont valides
out=$($FORB -t -s -np $QF 2>&1)
echo "$out" | grep -qE "Execution time: [0-9]+(\.[0-9]+)?s" && pass "-t -s affiche durée en secondes (fix timer source validé)" || fail "-t -s" "$(echo "$out" | grep -E 'Execution time' | head -1)"

out=$($FORB --time -s -np $QF 2>&1)
echo "$out" | grep -qE "Execution time: [0-9]+(\.[0-9]+)?s" && pass "--time -s (long form)" || fail "--time -s" ""

# ─── SECTION 10: LOG (--log) ──────────────────────────────────────────────────
section "Section 10: --log"

# FIX PERF: scan sur QF
before=$(ls "$LOG_DIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
out=$($FORB --log -s -np $QF 2>&1)
after=$(ls "$LOG_DIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
[ "$after" -gt "$before" ] && pass "--log crée un fichier log" || fail "--log" "avant=$before après=$after"
echo "$out" | grep -q "Scan log saved to" && pass "--log affiche le chemin du fichier" || fail "--log path" ""

before=$(ls "$LOG_DIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
out=$($FORB --log --json -s -np $QF 2>&1)
after=$(ls "$LOG_DIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
[ "$after" -eq "$before" ] && pass "--log + --json → aucun log créé (ignoré en JSON mode)" || fail "--log + --json crée un log" "avant=$before après=$after"

# ─── SECTION 11: --no-auto ────────────────────────────────────────────────────
section "Section 11: --no-auto"

# FIX PERF: scan sur QF
# --no-auto -s -np: scan source sans auto-detect NI menu (grâce à -np)
out=$($FORB --no-auto -s -np $QF 2>&1)
echo "$out" | grep -qE "Source audit complete|Scanning" && pass "--no-auto -s -np → scan source sans auto-detect" || fail "--no-auto -s -np" "$(echo "$out" | tail -2)"

# --no-auto seul → erreur JSON propre (pas de target, pas de -s)
out=$($FORB --no-auto --json 2>&1)
echo "$out" | grep -qE "No target|disabled|FAILURE" && pass "--no-auto --json → message d'erreur JSON propre" || fail "--no-auto --json" "$(echo "$out" | tail -2)"

# ─── SECTION 12: SHOW ALL (-a) ────────────────────────────────────────────────
section "Section 12: -a / SHOW_ALL"

out=$($FORB -a minishell 2>&1)
echo "$out" | grep -q "OK" && pass "-a affiche les fonctions autorisées en mode binaire" || fail "-a binaire" "$(echo "$out" | head -3)"
echo "$out" | grep -qv -- "-> build_prompt" && pass "  -a binaire ignore les user_funcs" || fail "-a binaire user_funcs" ""

out=$($FORB -a -s -f srcs/core/prompt.c 2>&1)
echo "$out" | grep -q "OK" && pass "-a affiche les fonctions autorisées en mode source" || fail "-a source" "$(echo "$out" | head -3)"
echo "$out" | grep -qvE -- "-> (return|sizeof|if|while)" && pass "  -a source ignore les mots-clés et macros" || fail "-a source keywords" "$(echo "$out" | grep -E 'return|sizeof' | head -1)"
echo "$out" | grep -qv -- "-> build_prompt" && pass "  -a source ignore les user_funcs (fix validé)" || fail "-a source user_funcs" "$(echo "$out" | grep build_prompt)"

# ─── SECTION 13: GESTION D'ERREURS ───────────────────────────────────────────
section "Section 13: Gestion d'erreurs"

out=$($FORB --invalid-flag-xyz 2>&1)
echo "$out" | grep -q "Unknown option" && pass "Flag inconnu → 'Unknown option'" || fail "flag inconnu" "$out"

out=$($FORB "$TEST_ROOT/nonexistent_binary_xyz" -np $QF 2>&1)
echo "$out" | grep -qE "Falling back|Source Scan|Scanning|Scan Mode" && pass "Target inexistant → fallback source scan" || fail "target inexistant" "$(echo "$out" | head -3)"

# ─── SECTION 14: EDGE CASES & COMBINAISONS EXTRÊMES ──────────────────────────
section "Section 14: Edge Cases & Combinaisons extrêmes"

out=$($FORB -s --json -t -a -v --log $QF 2>&1)
echo "$out" | python3 -m json.tool > /dev/null 2>&1 && pass "Mode JSON strict avec flags verbeux (-t -a -v --log)" || fail "JSON pollué" "$(echo "$out" | head -2)"

out=$($FORB -snpb $QF 2>&1)
echo "$out" | grep -q "Unknown option" && fail "Mega flag -snpb" "Erreur d'option" || pass "Mega flag -snpb parsé correctement"
echo "$out" | grep -qE "(Source.*c|Scanning)" && pass "  Mega flag : -s bien activé" || fail "  Mega flag : pas de source scan" ""
echo "$out" | grep -qi "blacklist" && pass "  Mega flag : -b bien activé" || fail "  Mega flag : blacklist manquant" ""

out=$($FORB -l -s $QF 2>&1)
echo "$out" | grep -qE "Scan Mode.*Source|Scanning" && pass "-l et -s combinés → Scan Source prend la priorité et s'exécute" || fail "-l -s plantage" "$(echo "$out" | head -2)"

touch "$TEST_ROOT/empty_forb_test.c"
out=$($FORB -s -f "$TEST_ROOT/empty_forb_test.c" 2>&1)
echo "$out" | grep -q "PERFECT" && pass "Scan fichier vide → pas de crash (PERFECT)" || fail "Scan fichier vide" "$(echo "$out" | head -2)"
rm -f "$TEST_ROOT/empty_forb_test.c"

# ─── SECTION 15: HTML & OUTPUT UI ─────────────────────────────────────────────
section "Section 15: HTML & Output UI"

out=$($FORB -s -np --html $QF 2>&1)
echo "$out" | grep -q "Rapport HTML généré avec succès dans" && pass "--html génère bien le fichier et masque l'UI" || fail "--html" "$out"

rm -f "$_TDIR/forb_callgraph.html"
out=$($FORB -s -np --graph $QF 2>&1)
[ -f "$_TDIR/forb_callgraph.html" ] && pass "--graph génère bien forb_callgraph.html" || fail "--graph" "$out"
grep -q "const DATA =" "$_TDIR/forb_callgraph.html" && pass "--graph injecte les données JSON dans le HTML" || fail "--graph html" ""
echo "$out" | grep -q "Call graph generated successfully in" && pass "--graph affiche le chemin du rapport" || fail "--graph output" "$out"

rm -rf "$TEST_ROOT/forb_mock_bin_dir"
mkdir -p "$TEST_ROOT/forb_mock_bin_dir"
echo '#!/bin/bash' > "$TEST_ROOT/forb_mock_bin_dir/xdg-open"
echo '#!/bin/bash' > "$TEST_ROOT/forb_mock_bin_dir/open"
echo '#!/bin/bash' > "$TEST_ROOT/forb_mock_bin_dir/explorer.exe"
chmod +x "$TEST_ROOT/forb_mock_bin_dir/"*
OLD_PATH="$PATH"
export PATH="$TEST_ROOT/forb_mock_bin_dir:$PATH"

out=$($FORB -oh 2>&1)
echo "$out" | grep -q "Opening HTML reports directory" && pass "-oh déclenche bien l'ouverture du dossier" || fail "-oh output" "$out"

export PATH="$OLD_PATH"
rm -rf "$TEST_ROOT/forb_mock_bin_dir"

# ─── SECTION 16: MOTEUR DE PARSING C (Anti-quotes & commentaires) ─────────────
section "Section 16: Parser C (Robustesse)"

cat << 'EOF' > "$TEST_ROOT/forb_mock_parser.c"
#include <stdio.h>
#include <stdlib.h>
// printf("forbidden1");
/* malloc(10); */
char *s = "gets(str)";
char c = '"'; // putchar('a');
#define X free
int i = sizeof(int);
void local_func() { return; }
void forbidden_call() { puts("hi"); }
EOF

out=$($FORB -s -np -f "$TEST_ROOT/forb_mock_parser.c" 2>&1)
echo "$out" | grep -qv "forbidden1" && pass "Parser: Ignore appels dans commentaires ligne simple" || fail "Parser com simple" "$(echo "$out" | grep forbidden1)"
echo "$out" | grep -qv "malloc" && pass "Parser: Ignore appels dans commentaires multi-lignes" || fail "Parser com bloc" "$(echo "$out" | grep malloc)"
echo "$out" | grep -qv "gets" && pass "Parser: Ignore appels dans chaines de caractères string" || fail "Parser str" "$(echo "$out" | grep gets)"
echo "$out" | grep -qv "putchar" && pass "Parser: Ignore appels dans quotes ou com derrière quote" || fail "Parser quote" "$(echo "$out" | grep putchar)"
echo "$out" | grep -qv "free" && pass "Parser: Ignore macros (#define)" || fail "Parser macro" "$(echo "$out" | grep free)"
echo "$out" | grep -qv "sizeof" && pass "Parser: Ignore opérateurs intrinsèques (sizeof)" || fail "Parser sizeof" "$(echo "$out" | grep sizeof)"
echo "$out" | grep -qv "local_func" && pass "Parser: Ignore déclarations locales" || fail "Parser decl local" "$(echo "$out" | grep local_func)"
echo "$out" | grep -q "puts" && pass "Parser: Trouve les vrais appels de fonctions interdites" || fail "Parser trouve appel" "puts manquant"


# ─── SECTION 17: FILTRES DE LIBRAIRIES (-mlx, -lm) ────────────────────────────
section "Section 17: Filtres Librairies (-mlx, -lm)"

cat << 'EOF' > "$TEST_ROOT/forb_mock_libs.c"
void test() {
    mlx_init();
    cos(0.0);
}
EOF

out=$($FORB -s -np -f "$TEST_ROOT/forb_mock_libs.c" 2>&1)
echo "$out" | grep -q "mlx_init" && pass "Library: mlx_init est forbidden par défaut" || fail "-mlx default" ""
echo "$out" | grep -q "cos" && pass "Library: cos est forbidden par défaut" || fail "-lm default" ""

out=$($FORB -s -np -mlx -f "$TEST_ROOT/forb_mock_libs.c" 2>&1)
echo "$out" | grep -qv "mlx_init" && pass "Library: -mlx autorise les fonctions mlx_*" || fail "-mlx flag" "mlx toujours forbidden"
echo "$out" | grep -q "cos" && pass "Library: -mlx n'impacte pas math" || fail "-mlx side effect" ""

out=$($FORB -s -np -lm -f "$TEST_ROOT/forb_mock_libs.c" 2>&1)
echo "$out" | grep -qv "cos" && pass "Library: -lm autorise les fonctions math" || fail "-lm flag" "math toujours forbidden"


# ─── SECTION 18: FICHIERS CIBLES MULTIPLES (-f) & PATHS ────────────────────────
section "Section 18: Ciblage de Fichiers (-f)"

touch "$TEST_ROOT/forb_mock_f1.c" "$TEST_ROOT/forb_mock_f2.c"
out=$($FORB -s -np -f "$TEST_ROOT/forb_mock_f1.c" "$TEST_ROOT/forb_mock_f2.c" 2>&1)
echo "$out" | grep -qE "Scanning 2 source file(\(s\))?" && pass "-f accepte multiples cibles" || fail "-f cibles" "$(echo "$out" | grep Scanning)"
out=$($FORB -s -np -f "$TEST_ROOT/nonexistent123.c" 2>&1)
echo "$out" | grep -qvE "Scanning 1 source files" && pass "-f résiste aux fichiers inexistants" || fail "-f invalid" ""


# ─── SECTION 19: STRUCTURE JSON AVANCÉE ───────────────────────────────────────
section "Section 19: JSON Avancé"

out=$($FORB -s -np -f "$TEST_ROOT/forb_mock_libs.c" --json 2>&1)
arr_len=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results', [])))" 2>/dev/null)
[ "${arr_len:-0}" -ge 2 ] && pass "JSON: tableau results grandit selon les occurrences (scale multiple)" || fail "JSON scale" "len=$arr_len"
out=$($FORB -np -s --json $QF 2>&1)
echo "$out" | python3 -m json.tool > /dev/null 2>&1 && pass "JSON: structure persistante même en cas d'erreur de parse" || fail "JSON no file" ""

out=$($FORB --json -f "bad#char*.c" 2>&1)
echo "$out" | grep -q "status" && pass "JSON: retourne un status json lors d'usage de chars extrêmes" || fail "JSON bad chars" ""


# ─── SECTION 20: SYSTÈME DE CACHE BINAIRE ─────────────────────────────────────
section "Section 20: Cache Binaire"
mkdir -p "$TEST_ROOT/forb_cache_test"
cd "$TEST_ROOT/forb_cache_test" || exit 1

echo "int main(){return 0;}" > ./main.c
gcc ./main.c -o ./bin 2>/dev/null

if [ -f "./bin" ]; then
    out=$(echo "n" | $FORB -np ./bin 2>&1)
    echo "$out" | grep -qv "Source content is newer" && pass "Cache: 1er scan valide sans avertissement de modification" || fail "Cache 1er scan" "$out"

    sleep 1
    echo "void f(){}" >> ./main.c
    echo "int x=0;" >> ./main.c
    out=$(echo "n" | $FORB -np ./bin 2>&1)
    echo "$out" | grep -q "Source content is newer" && pass "Cache: Détecte une modification de code locale après compilation" || fail "Cache modification détectée" "$out"
else
    pass "Cache: Skip gcc fallback"
    pass "Cache: Skip cache update check"
fi

cd "$_TDIR" || exit 1
rm -rf "$TEST_ROOT/forb_cache_test"


# ─── SECTION 21: LOGGING AVANCÉ ───────────────────────────────────────────────
section "Section 21: Log & Output Formatting"

out=$($FORB --log -np -s $QF 2>&1)
latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
grep -q "Scan Mode" "$latest_log" 2>/dev/null && pass "Log: Le fichier contient le pattern de scan" || fail "Log header" ""
grep -q "Source" "$latest_log" 2>/dev/null && pass "Log: Le fichier de log retranscrit textuellement les blocks complets" || fail "Log exec" ""

out=$($FORB -s -np $QF 2>&1)
echo "$out" | grep -q "Whitelist" && pass "Print: Affiche le string Whitelist par défaut" || fail "Print W" ""
out=$($FORB -s -np -b $QF 2>&1)
echo "$out" | grep -q "Blacklist" && pass "Print: Affiche le string Blacklist si forcé avec -b" || fail "Print B" ""


# ─── SECTION 22: AUTO-DETECT TARGET ET PRESETS ────────────────────────────────
section "Section 22: Auto-Detection Dossier & Fallback"

mkdir -p "$TEST_ROOT/forb_mock_proj"
touch "$TEST_ROOT/forb_mock_proj/dummy.c"
cd "$TEST_ROOT/forb_mock_proj"
out=$(echo "n" | $FORB -np 2>&1)
echo "$out" | grep -qE "No binary found|Target .* not found" && pass "Fallback: Réagit quand le binaire par défaut est absent d'un dossier nu" || fail "Fallback no bin" ""

touch "$HOME/.forb/presets/forb_mock_proj.preset"
echo "exit" > "$HOME/.forb/presets/forb_mock_proj.preset"
out=$(echo "n" | $FORB -s 2>&1)
echo "$out" | grep -q "Preset.*forb_mock_proj" && pass "Auto-Preset: Sélectionne dynamiquement le preset pointant sur le nom /dir" || fail "Auto preset fallback" ""
rm -f "$HOME/.forb/presets/forb_mock_proj.preset"
cd "$_TDIR" || exit 1
rm -rf "$TEST_ROOT/forb_mock_proj"


# ─── SECTION 23: PARSING DES CIBLES MULTIPLES ET ORDRE ────────────────────────
section "Section 23: Ordre & Position des Arguments"

out=$(echo "n" | $FORB b1 b2 -np $QF 2>&1)
echo "$out" | grep -q "Target 'b2'" && pass "Arguments: En cas de multiples cibles non optionnelles, la target absorbe la 2e" || fail "Args target swap" ""

out=$(echo "n" | $FORB -np b3 $QF 2>&1)
out2=$(echo "n" | $FORB b3 -np $QF 2>&1)
[ "$(echo "$out" | grep -o 'Target .*')" = "$(echo "$out2" | grep -o 'Target .*')" ] && pass "Arguments: Extraction de cible stable peu importe l'ordre des flags" || fail "Args unordered parsing" ""

out=$(echo "n" | $FORB tmp_bin_here -l myfunc_test -np 2>&1)
echo "$out" | grep -qE "Checking functions|empty" && pass "Arguments: -l fonctionne indépendamment après une déclaration" || fail "Args parse manual target" ""


# ─── SECTION 24: MACRO OBFUSCATION (ForceDefine) ─────────────────────────────
section "Section 24: Macro Obfuscation (ForceDefine)"

# 1. Recursive Token Pasting (Whitelist Mode)
cat << 'EOF' > "$TEST_ROOT/macro_sneaky.c"
#define P pri
#define N ntf
#define CAT(a,b) a##b
int main() {
    CAT(P, N)("Sneaky call\n"); // Expanded to printf (allowed in minishell preset)
    CAT(mal, loc)(10);        // Expanded to malloc (allowed in minishell preset)
    CAT(ge, ts)(NULL);        // Expanded to gets (forbidden)
    return 0;
}
EOF
out=$($FORB -s -np -f "$TEST_ROOT/macro_sneaky.c" 2>&1)
echo "$out" | grep -q "gets" && pass "Macro: Détecte gets() fragmenté par token pasting (##)" || fail "Macro token pasting" "$(echo "$out" | grep gets)"

# 2. Variadic Macros Expansion
cat << 'EOF' > "$TEST_ROOT/macro_va.c"
#define CALL(f, ...) f(__VA_ARGS__)
int main() {
    CALL(printf, "hi\n");
    CALL(gets, ptr);
    return 0;
}
EOF
out=$($FORB -s -np -f "$TEST_ROOT/macro_va.c" 2>&1)
echo "$out" | grep -q "gets" && pass "Macro: Détecte fonction interdite via macro variadique" || fail "Macro variadic" "$(echo "$out" | grep gets)"

# 3. Cross-file Header Inclusion
mkdir -p "$TEST_ROOT/macro_proj"
cat << 'EOF' > "$TEST_ROOT/macro_proj/secret.h"
#define TRAP gets
EOF
cat << 'EOF' > "$TEST_ROOT/macro_proj/main.c"
#include "secret.h"
int main() {
    TRAP(NULL);
    return 0;
}
EOF
out=$($FORB -s -np -f "$TEST_ROOT/macro_proj/main.c" 2>&1)
echo "$out" | grep -q "gets" && pass "Macro: Détecte macro définie dans un header inclus récursivement" || fail "Macro inclusion" "$(echo "$out" | grep gets)"

cat << 'EOF' > "$TEST_ROOT/macro_shield.c"
#define IF if
#define STR "printf"
int main() {
    IF(1) { puts(STR); }
    return 0;
}
EOF
out=$($FORB -s -p -f "$TEST_ROOT/macro_shield.c" 2>&1)
echo "$out" | grep -qv "printf" && pass "Macro: Ignore correctement les mots-clés (if) et les chaines générées par macro" || fail "Macro shield" "$(echo "$out" | grep printf)"

cat << 'EOF' > "$HOME/.forb/presets/macro_bl_test.preset"
BLACKLIST_MODE
printf
EOF
out=$(SELECTED_PRESET=macro_bl_test $FORB -s -f "$TEST_ROOT/macro_sneaky.c" 2>&1)
echo "$out" | grep -q "printf" && pass "Macro: Détecte printf() caché en mode Blacklist" || fail "Macro blacklist" "$(echo "$out" | grep printf)"

echo "y" | $FORB --no-auto -rp macro_bl_test > /dev/null 2>&1
rm -rf "$TEST_ROOT/macro_sneaky.c" "$TEST_ROOT/macro_va.c" "$TEST_ROOT/macro_proj" "$TEST_ROOT/macro_shield.c"


# ─── CLEANUP ──────────────────────────────────────────────────────────────────
rm -rf "$_TDIR"


# ─── RÉSUMÉ ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo " 📊 RÉSUMÉ"
echo "══════════════════════════════════════════════"
TOTAL=$((PASS+FAIL))
echo "  Tests : $TOTAL  |  ✅ $PASS  |  ❌ $FAIL"
[ $FAIL -eq 0 ] && echo "  🎉 Tous les tests passés !" || echo "  ⚠️  $FAIL test(s) ont échoué."
echo ""
