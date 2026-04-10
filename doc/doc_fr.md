# DOCUMENTATION COMPLÈTE - ForbCheck (forb.sh)

**Version :** 1.16.0
**Auteur :** Mrdolls
**Date de mise à jour :** 2026-04-10
**Repository :** https://github.com/Mrdolls/forbCheck

---

## 📖 Table des matières

1. [Présentation générale](#présentation-générale)
2. [Installation & Configuration](#installation--configuration)
3. [Syntaxe générale](#syntaxe-générale)
4. [Flags & Options](#flags--options)
5. [Comportements par défaut](#comportements-par-défaut)
6. [Modes d'exécution](#modes-dexécution)
7. [Presets](#presets)
8. [Cas d'usage avancés](#cas-dusage-avancés)
9. [Gestion des erreurs](#gestion-des-erreurs)
10. [Exemples pratiques](#exemples-pratiques)

---

## Présentation générale

**ForbCheck** est un outil d'analyse statique et dynamique conçu pour détecter l'utilisation de fonctions interdites ou non autorisées dans des projets C/C++. L'outil peut analyser :

- **Binaires compilés** : Via extraction de symboles avec `nm`
- **Fichiers sources** : Via recherche de pattern dans les fichiers `.c`
- **Bibliothèques liées** : Détection automatique des dépendances

### Principe fondamental

ForbCheck fonctionne sur la base de **listes de fonctions** stockées dans des **presets** (fichiers `.preset`). Chaque preset définit un ensemble de règles pour un projet donné.

**Mode par défaut (Whitelist)** : Les fonctions listées sont **autorisées**.
**Mode blacklist** : Les fonctions listées sont **interdites** (inversion de logique).

---

## Installation & Configuration

### Répertoires clés

| Répertoire | Chemin | Description |
|-----------|--------|-------------|
| Installation | `~/.forb/` | Répertoire racine (créé automatiquement) |
| Bibliothèque | `~/.forb/lib/` | Modules internes (Shell & Perl) constituant le cœur |
| Presets | `~/.forb/presets/` | Stockage des fichiers `.preset` |
| Logs | `~/.forb/logs/` | Fichiers logs générés avec `--log` |
| Rapports HTML | `~/.forb/reports_html/` | Fichiers HTML générés avec `--html` |

### Dépendances requises

L'outil nécessite les commandes suivantes pour fonctionner :

| Commande | Utilité |
|----------|---------|
| `nm` | Extraction des symboles des binaires |
| `perl` | Traitement et analyse des données |
| `curl` | Téléchargement des presets |
| `tar` | Extraction des archives |
| `bc` (optionnel) | Calcul du temps d'exécution (`-t`) |

Si une dépendance manque, ForbCheck affichera une erreur et quittera avec le code 1.

---

## Syntaxe générale

```bash
./forb.sh [OPTIONS] [TARGET] [-f FILES...]
```

### Composants

- **OPTIONS** : Drapeaux de contrôle (ordre flexible, voir section FLAGS)
- **TARGET** : Chemin vers le binaire ou dossier source à analyser (optionnel si `-s` ou `--no-auto`)
- **-f FILES...** : Liste de fichiers/symboles spécifiques à analyser (après le flag `-f`)

### Points clés sur la syntaxe

1. **L'ordre des options est flexible** : `forb -s -v <target>` = `forb -v -s <target>`
2. **Les flags courts peuvent être combinés** : `forb -svpa <target>` = `forb -s -v -p -a <target>`
3. **Les flags longs ne se combinent pas** : `--preset --scan-source` (utilisez les formes courtes)
4. **TARGET doit être distinct de -f** : TARGET identifie le projet, -f spécifie les fichiers à scanner
5. **-f doit être suivi de fichiers** : `forb <target> -f file1.c file2.c` (le flag consomme tous les arguments suivants jusqu'au prochain flag)

---

## Flags & Options

### 📌 OPTIONS DE AIDE & INFORMATION

#### `-h` / `--help`

**Syntaxe :**
```bash
./forb.sh -h
./forb.sh --help
```

**Description :** Affiche le menu d'aide complet avec la liste de tous les drapeaux disponibles et leurs descriptions.

**Comportement :**
- Affiche un texte formaté avec toutes les options disponibles
- Quitte immédiatement après l'affichage (exit code 0)
- Ne nécessite pas de target

**Exemple :**
```bash
./forb.sh --help
```

---

#### `--version`

**Syntaxe :**
```bash
./forb.sh --version
```

**Description :** Affiche le numéro de version de ForbCheck.

**Comportement :**
- Affiche la version au format `V1.11.0`
- Quitte immédiatement (exit code 0)
- Ne nécessite pas de target

**Exemple :**
```bash
./forb.sh --version
# Output: V1.16.0
```

---

### 📊 OPTIONS DE SORTIE & LOGGING

#### `--json`

**Syntaxe :**
```bash
./forb.sh --json [OPTIONS] <target>
```

**Description :** Bascule la sortie en format JSON au lieu du texte coloré.

**Comportement :**
- Tout l'affichage texte coloré est supprimé
- La sortie complète est au format JSON valide
- Les informations de scan sont incluses dans le JSON
- Le flag `--log` est ignoré en mode JSON (pas de fichier log texte)
- À la fin du scan, affiche un objet JSON structuré

**Sortie JSON (structure) :**
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

**Cas particulier :**
- Si aucune fonction interdite n'est trouvée, `status` = `"PERFECT"` et `forbidden_count` = 0
- En mode source (`-s`), les locations incluent le numéro de ligne exact

**Exemple :**
```bash
./forb.sh --json ./my_binary | jq '.forbidden_count'
```

---

#### `--html`

**Syntaxe :**
```bash
./forb.sh --html [OPTIONS] <target>
```

**Description :** Exporte les résultats sous forme de rapport web interactif (avec UI avancée) au lieu du terminal habituel.

**Comportement :**
- L'interface standard du terminal est mise sous-silence (masquée).
- Crée un fichier de rapport stylisé (moderne, dynamique) dans `~/.forb/reports_html/`.
- Affiche uniquement le chemin absolu vers le fichier nouvellement créé.
- Conserve son code statuts système respectif (Exit 1 en cas d'erreurs, 0 si *Perfect*).

**Exemple :**
```bash
./forb.sh -s -np --html
# Output: ℹ Rapport HTML généré avec succès dans : /home/user/.forb/reports_html/forb_report_2026-04-06_21h10.html
```

---

#### `-oh` ou `--open-html`

**Syntaxe :**
```bash
./forb.sh -oh
```

**Description :** Ouvre instantanément le dossier hébergeant l'intégralité des rapports HTML générés via l'explorateur ou le gestionnaire de fichier natif du système hôte.

**Comportement :**
- Utilise la commande d'interface graphique universelle (`xdg-open`, `open` macOS ou `explorer.exe` Windows-Linux).
- Quitte immédiatement sa propre exécution juste après ouverture directe de la fenêtre.

**Exemple :**
```bash
./forb.sh -oh
```

---

#### `-ol` ou `--open-logs`

**Syntaxe :**
```bash
./forb.sh -ol
```

**Description :** Ouvre instantanément le dossier hébergeant les fichiers logs générés via `--log`.

**Comportement :**
- Utilise la commande d'interface graphique universelle (`xdg-open`, `open` macOS ou `explorer.exe`).
- Quitte immédiatement après ouverture du dossier.

**Exemple :**
```bash
./forb.sh -ol
```

---

#### `--log`

**Syntaxe :**
```bash
./forb.sh --log [OPTIONS] <target>
```

**Description :** Active la sauvegarde des logs dans un fichier.

**Comportement :**
- Crée un fichier log dans `~/.forb/logs/`
- Format du nom : `l<N>_YYYY-MM-DD_HHhMM.log` (où N est un compteur)
- Chaque scan génère un nouveau fichier numéroté
- À la fin du scan, affiche le chemin du fichier log créé
- Tous les messages texte (sans couleurs ANSI) sont écrits dans le fichier
- **Compatible avec les autres flags**

**Interaction avec `--json` :**
- Si `--json` est utilisé avec `--log`, le JSON est affiché et aucun fichier log n'est créé
- La sauvegarde de logs ne s'applique que en mode texte

**Exemple :**
```bash
./forb.sh --log ./my_binary
# Output: ℹ Scan log saved to: /home/user/.forb/logs/l1_2026-04-06_14h32.log
```

**Vérification du log :**
```bash
cat ~/.forb/logs/l1_*.log
```

---

#### `-t` / `--time`

**Syntaxe :**
```bash
./forb.sh -t <target>
./forb.sh --time <target>
```

**Description :** Affiche la durée d'exécution du scan en secondes.

**Comportement :**
- Mesure le temps à partir du démarrage du scan jusqu'à la fin
- Affiche la durée avant le résultat final (PERFECT ou FAILURE)
- Format : nombre décimal en secondes (ex: `1.234`)
- **Dépend de `bc`** : Si `bc` n'est pas installé, affiche `0`

**Implémentation :**
- Sur macOS : utilise `perl -MTime::HiRes=time`
- Sur Linux : utilise `date +%s.%N`

**Exemple :**
```bash
./forb.sh -t ./my_binary
```

---

#### `-A` / `--analyse`

**Syntaxe :**
```bash
./forb.sh -A
./forb.sh --analyse
```

**Description :** Ouvre le tableau de bord interactif (TUI) pour une analyse profonde de la structure du projet C/C++.

**Fonctionnalités du Dashboard :**
- **Interface TUI Premium** : Design Cyan/Vert dynamique avec navigation clavier intuitive.
- **Classification Automatique** : Sépare les fonctions internes (vos sources) des appels externes (système/libc).
- **Deep Macro Scan** : Analyse récursive des `#define` pour débusquer les fonctions cachées au cœur de macros complexes.
- **Navigation par Fichiers** : Exploration de l'intégralité des fichiers du projet (incluant les Headers).
- **Filtrage Intelligent des Macros** : Onglets horizontaux pour trier les macros (Header Guards, Numeric, Strings, etc.).

**Comportement :**
- Utilise le **Skeleton Parsing** pour détecter les signatures de fonctions complexes.
- **Zéro Faux Positif** : Si une définition existe, elle ne sera jamais marquée comme externe.
- Génère un journal d'audit complet dans `~/.forb/logs/analyse_engine.log`.

---

### 🔍 OPTIONS DE SCAN SOURCE

#### `-s` / `--scan-source`

**Syntaxe :**
```bash
./forb.sh -s [OPTIONS] [TARGET]
./forb.sh --scan-source [OPTIONS] [TARGET]
```

**Description :** Force l'analyse des fichiers source C/C++ au lieu d'un binaire.

**Comportement :**
- Bascule le mode en scan source
- Recherche les fichiers `*.c` dans le répertoire courant ou TARGET
- Utilise `grep` pour détecter les appels de fonction dans le code
- Retourne le numéro de ligne exact de chaque occurrence
- **TARGET est optionnel** : si absent, scanne le répertoire courant

**Mode source vs mode binaire :**
- **Source** : Détecte les appels de fonctions dans le code (plus sensible aux faux positifs)
- **Binaire** : Détecte les symboles liés au binaire (plus fiable)

**Exemple :**
```bash
./forb.sh -s                    # Scanne sources du répertoire courant
./forb.sh -s /path/to/project   # Scanne sources du projet
./forb.sh -s -f file1.c file2.c # Scanne fichiers spécifiques
```

---

#### `-v` / `--verbose`

**Syntaxe :**
```bash
./forb.sh -v [OPTIONS] <target>
./forb.sh --verbose [OPTIONS] <target>
```

**Description :** Active le mode verbeux pour afficher plus de détails lors du scan.

**Comportement :**
- Augmente la quantité d'informations affichées
- Spécifiquement utile en mode source (`-s`)
- Affiche les fichiers en cours de traitement
- Montre les correspondances détaillées avec contexte

**Exemple :**
```bash
./forb.sh -s -v              # Mode source verbeux
./forb.sh -v ./binary        # Mode binaire verbeux
```

---

#### `-p` / `--full-path`

**Syntaxe :**
```bash
./forb.sh -p [OPTIONS] <target>
./forb.sh --full-path [OPTIONS] <target>
```

**Description :** Affiche les chemins **absolus** au lieu des chemins relatifs.

**Comportement :**
- Convertit tous les chemins en chemins absolus (commençant par `/`)
- Utile pour scripter ou intégrer à des outils externes
- Affecte l'affichage texte et JSON

**Exemple :**
```bash
./forb.sh -p -s              # Affiche /path/to/file.c au lieu de ./file.c
```

**Cas particulier :**
- Les chemins relatifs commençant par `./` sont nettoyés automatiquement même sans `-p`

---

#### `-a` / `--all`

**Syntaxe :**
```bash
./forb.sh -a [OPTIONS] <target>
```

**Description :** Affiche **toutes les occurrences** de chaque fonction interdite.

**Comportement :**
- Par défaut, le script peut limiter les résultats affichés
- Avec `-a`, affiche chaque ligne où la fonction est utilisée
- Augmente la quantité de résultats
- Particulièrement utile en mode source

**Exemple :**
```bash
./forb.sh -a -s              # Toutes les occurrences en mode source
./forb.sh -a ./binary        # Toutes les occurrences en mode binaire
```

---

#### `-f [FILES...]`

**Syntaxe :**
```bash
./forb.sh <target> -f file1 file2 file3
./forb.sh -s -f lib1.c lib2.c lib3.c
```

**Description :** Limite le scan à des fichiers/symboles spécifiques.

**Comportement :**
- **IMPORTANT** : Le flag `-f` consomme tous les arguments suivants jusqu'au prochain flag
- Doit être placé **après** le TARGET (si celui-ci existe)
- En mode source : scanne seulement les fichiers `.c` listés
- En mode binaire : filtre les symboles à analyser
- Peut être utilisé avec `-s` ou sans

**Points critiques :**
1. `-f` doit être le **dernier flag** (il consomme le reste)
2. Les fichiers doivent être séparés par des espaces
3. Un regex ou pattern n'est pas supporté (fichiers exacts seulement)

**Exemple :**
```bash
./forb.sh -s -f main.c utils.c parser.c
./forb.sh ./binary -f symbol1 symbol2
./forb.sh -s -v -f file1.c file2.c
```

---

### 🎯 OPTIONS DE MODE BLACKLIST/WHITELIST

#### `-b` / `--blacklist`

**Syntaxe :**
```bash
./forb.sh -b [OPTIONS] <target>
./forb.sh --blacklist [OPTIONS] <target>
```

**Description :** Active le **mode blacklist** (inversion logique).

**Comportement par défaut (Whitelist) :**
- Les fonctions **listées dans le preset** sont **autorisées**
- Les résultats affichent l'usage de fonctions **non listées**
- Logique : "Seules ces fonctions sont OK"

**Comportement en mode Blacklist (-b) :**
- Les fonctions **listées dans le preset** sont **interdites**
- Les résultats affichent les violations (usage de fonctions interdites)
- Logique : "Toute fonction non dans la liste est OK"

**Exemple :**
```bash
# Whitelist (Défaut) : Le preset contient "printf malloc" (seules autorisées)
./forb.sh ./binary
# Affiche les violations pour toute autre fonction (ex: strcpy found...)

# Blacklist (-b) : Le preset contient "system execve" (fonctions interdites)
./forb.sh -b ./binary
# Affiche une violation UNIQUEMENT si system ou execve sont trouvées
```

**Marquer mode blacklist dans le preset :**
Dans le fichier `.preset`, ajoutez la ligne suivante pour que le preset active automatiquement le mode blacklist :
```
BLACKLIST_MODE
```

---

### 📋 OPTIONS DE LISTE & VÉRIFICATION

#### `-l` / `--list`

**Syntaxe :**
```bash
./forb.sh -l [TARGET] [FUNC1 FUNC2 ...]
./forb.sh --list [TARGET] [FUNC1 FUNC2 ...]
```

**Description :** Affiche la liste des fonctions chargées du preset **sans effectuer de scan**.

**Comportement :**
- Charge le preset approprié
- Affiche toutes les fonctions ou juste celles spécifiées
- Ne scanne aucun binaire ou source
- Quitte après affichage

**Variantes :**

1. **Afficher toute la liste :**
```bash
./forb.sh -l <target>
# Output:
# Listed functions (Whitelist):
# strcpy   strcat   gets     ...
```

2. **Vérifier des fonctions spécifiques :**
```bash
./forb.sh -l <target> strcpy printf strlen
# Output:
# [OK] -> strcpy (in list)
# [KO] -> printf (not in list)
# [OK] -> strlen (in list)
```

**Avec mode blacklist :**
```bash
./forb.sh -l -b <target> strcpy printf
# Output:
# [KO] -> strcpy (Blacklisted - not allowed)
# [OK] -> printf (Allowed)
```

---

### 🎛️ OPTIONS DE PRESETS

#### `--preset` / `-P`

**Syntaxe :**
```bash
./forb.sh --preset <target>
./forb.sh -P <target>
```

**Description :** Force la sélection **interactive** du preset.

**Comportement :**
- Affiche un menu numéroté avec tous les presets disponibles
- Attend l'entrée utilisateur (numéro)
- Charge le preset sélectionné
- Peut être utilisé seul ou avec d'autres options

**Exemple :**
```bash
./forb.sh -P ./my_binary
# Output:
# Select a project preset:
# 1) default
# 2) minishell
# 3) so_long
# Enter the number of your preset:
```

**Cas d'erreur :**
- Si l'environnement n'est pas interactif, affiche une erreur
- Si aucune sélection n'est faite, quitte avec code 1

---

#### `-np` / `--no-preset`

**Syntaxe :**
```bash
./forb.sh -np <target>
./forb.sh --no-preset <target>
```

**Description :** **Désactive** les presets et utilise une liste vide.

**Comportement :**
- Ignore complètement les fichiers presets
- Utilise le preset `default` qui est vide
- Utile pour vérifier qu'aucune fonction interdite n'est utilisée (trivial)
- Aucune fonction n'est listée comme interdite

**Exemple :**
```bash
./forb.sh -np ./my_binary
# Output: RESULT: PERFECT (car aucune fonction n'est interdite)
```

---

#### `-lp` / `--list-presets`

**Syntaxe :**
```bash
./forb.sh -lp
./forb.sh --list-presets
```

**Description :** Affiche la liste de tous les presets disponibles.

**Comportement :**
- Scanne le répertoire `~/.forb/presets/`
- Affiche les noms des presets (sans l'extension `.preset`)
- Quitte immédiatement après (exit code 0)
- Ne nécessite pas de target

**Exemple :**
```bash
./forb.sh -lp
# Output:
# Available presets: default, minishell, so_long, ft_printf, libft
```

---

#### `-cp` / `--create-presets`

**Syntaxe :**
```bash
./forb.sh -cp
./forb.sh --create-presets
```

**Description :** Lance le processus interactif de **création** d'un nouveau preset.

**Comportement :**
- Demande le nom du preset (remplace les espaces par des tirets)
- Crée un fichier `.preset` avec un template
- Ouvre automatiquement l'éditeur pour éditer le fichier
- Sauvegarde et quitte

**Éditeur utilisé (dans cet ordre) :**
1. VS Code (`code`)
2. Vim (`vim`)
3. Nano (`nano`)

**Exemple :**
```bash
./forb.sh -cp
# Output:
# Enter the name of the new preset (e.g., minishell): my_project
# Creating new preset 'my_project'...
# [Editor opens with template]
# [✔] Preset 'my_project' saved!
```

**Template généré :**
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

**Syntaxe :**
```bash
./forb.sh -gp
./forb.sh --get-presets
```

**Description :** **Télécharge** les presets par défaut depuis le dépôt GitHub.

**Comportement :**
- Télécharge depuis : `https://github.com/Mrdolls/forbCheck`
- Demande confirmation avant d'écraser les presets existants
- Ajoute les nouveaux presets (ne supprime pas les existants)
- Utilise `curl` et `tar`

**Modes :**

1. **Mode manuel (depuis CLI) :**
```bash
./forb.sh -gp
# Output:
# Warning: This will download default presets...
# Continue? (y/n): y
# Downloading presets...
# [✔] Default presets successfully restored!
```

2. **Mode automatique (lors d'une mise à jour) :**
- Lors d'une mise à jour (`-up`), les presets manquants sont téléchargés silencieusement
- Les presets existants ne sont jamais overwrités

---

#### `-op` / `--open-presets`

**Syntaxe :**
```bash
./forb.sh -op
./forb.sh --open-presets
```

**Description :** Ouvre le répertoire des presets dans l'**explorateur de fichiers**.

**Comportement :**
- Détecte le système d'exploitation
- Ouvre le dossier `~/.forb/presets/` avec l'explorateur natif
- Quitte immédiatement après

**Gestionnaires de fichiers utilisés (selon l'OS) :**
- **Windows** : `explorer.exe`
- **Linux** : `xdg-open`
- **macOS** : `open`

**Exemple :**
```bash
./forb.sh -op
# Ouvre le dossier des presets dans Finder (macOS) ou l'explorateur (Windows)
```

---

#### `-rp` / `--remove-preset`

**Syntaxe :**
```bash
./forb.sh -rp
./forb.sh --remove-preset
```

**Description :** **Supprime** un preset existant.

**Comportement :**
- Affiche la liste des presets disponibles
- Demande le nom du preset à supprimer
- Demande confirmation avant suppression
- Quitte après

**Protections :**
- Le preset `default` ne peut **pas** être supprimé
- Demande confirmation avant chaque suppression

**Exemple :**
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

**Syntaxe :**
```bash
./forb.sh -e [TARGET]
```

**Description :** **Édite** la liste manuelle de fonctions (preset actif).

**Comportement :**
- Ouvre l'éditeur pour le preset actuellement chargé
- Crée le fichier s'il n'existe pas
- Utilise le même éditeur que `-cp` (code > vim > nano)
- Quitte après édition

**Exemple :**
```bash
./forb.sh -e
# Demande quel preset ouvrir et l'ouvre dans l'éditeur pour l'editer
```

---

### 🔧 OPTIONS BINAIRES & ARCHITECTURE

#### `-mlx`

**Syntaxe :**
```bash
./forb.sh -mlx <target>
```

**Description :** Active le **mode MiniLibX** (filtre les symboles MLX internes).

**Comportement :**
- Filtre automatiquement les symboles MiniLibX (`mlx_*`)
- Utile pour les projets 42 utilisant MiniLibX
- Évite les faux positifs sur les fonctions MLX
- Peut être combiné avec `-lm`

**Détection automatique :**
ForbCheck détecte automatiquement MiniLibX si :
- Un dossier `*mlx*` ou `*minilibx*` existe dans le projet
- Le binaire contient des symboles `mlx_*`

**Désactiver auto-détection :**
```bash
./forb.sh --no-auto -mlx <target>  # Force le mode MLX
./forb.sh --no-auto ./binary        # Scanne sans détection automatique
```

---

#### `-lm`

**Syntaxe :**
```bash
./forb.sh -lm <target>
```

**Description :** Active l'analyse de la **bibliothèque mathématique** (`libm`).

**Comportement :**
- Autorise (ou filtre) les fonctions mathématiques (`sin`, `cos`, `sqrt`, etc.)
- Détecte automatiquement si le Makefile inclut `-lm`
- Détecte automatiquement les symboles math liés au binaire
- Peut être combiné avec `-mlx`

**Fonctions affectées :**
```
sin, cos, tan, asin, acos, atan, atan2,
sinh, cosh, tanh,
exp, log, log10, sqrt, pow, fabs,
floor, ceil, round, trunc
```

**Cas d'usage :**
```bash
./forb.sh -lm ./my_physics_engine
```

---

### 🔄 OPTIONS DE MAINTENANCE

#### `-up` / `--update`

**Syntaxe :**
```bash
./forb.sh -up
./forb.sh --update
```

**Description :** **Met à jour** le script ForbCheck à la version la plus récente.

**Comportement :**
- Télécharge la version la plus récente depuis GitHub
- Compare la version locale avec celle du dépôt
- Demande confirmation avant de mettre à jour
- Télécharge depuis : `https://raw.githubusercontent.com/Mrdolls/forbCheck/main/forb.sh`
- Ajoute automatiquement les nouveaux presets manquants

**Exemple :**
```bash
./forb.sh --update
# Output:
# Checking for updates...
# New version available: v1.14.5 (Current: v1.12.0)
# Update? (y/n): y
# [✔] Update successful!
```

**Interaction avec presets :**
- Les presets existants ne sont **jamais** overwrités
- Les nouveaux presets du dépôt sont ajoutés automatiquement

---

#### `--remove`

**Syntaxe :**
```bash
./forb.sh --remove
```

**Description :** **Désinstalle** complètement ForbCheck.

**Comportement :**
- Supprime le répertoire `~/.forb/`
- Supprime l'alias shell `forb`
- Supprime les configurations d'autocomplétion
- Nettoie `.bashrc` et `.zshrc`
- Demande confirmation avant suppression

**Exemple :**
```bash
./forb.sh --remove
# Output:
# Are you sure you want to remove ForbCheck? (y/n): y
# [✔] ForbCheck has been successfully removed.
# Note: Run 'exec zsh' to refresh your shell.
```

---

### ⚙️ OPTIONS DE CONTRÔLE GLOBAL

#### `--no-auto`

**Syntaxe :**
```bash
./forb.sh --no-auto [OPTIONS] <target>
./forb.sh --no-auto -s
```

**Description :** **Désactive** les détections automatiques.

**Auto-détections désactivées :**
1. **Auto-détection du binaire** : Ne cherche pas un binaire via le Makefile
2. **Auto-détection du preset** : Ne cherche pas à matcher le target au preset
3. **Auto-détection des bibliothèques** : N'active pas automatiquement `-mlx` ou `-lm`
4. **Fallback source** : Si le binaire n'est pas trouvé, ne bascule pas en scan source

**Comportement avec `--no-auto` :**
- Exige un TARGET explicite ou une action non-scan (`-l`, `-e`, etc.)
- Force le mode "strict"
- Affiche les messages "[Auto-Detect]" comme désactivés

**Cas d'usage :**
- En environnement non-interactif (CI/CD)
- Pour éviter les surprises d'auto-détection
- Pour forcer un comportement explicite

**Exemple :**
```bash
./forb.sh --no-auto ./my_binary
# Scanne ./my_binary sans aucune détection automatique

./forb.sh --no-auto --no-auto
# Erreur : Target required avec --no-auto
```

---

## Comportements par défaut

### Scan par défaut

Quand vous lancez :
```bash
./forb.sh <target>
```

L'outil exécute cette séquence :

1. **Vérification du target** :
   - Si c'est un fichier binaire existant → scan binaire
   - Si ce n'est pas un fichier → fallback en scan source
   - Si aucun target : auto-détection + prompt preset

2. **Détection automatique** :
   - Cherche le binaire via le Makefile (`NAME=`)
   - Détecte MiniLibX (`mlx_*` symboles ou dossier)
   - Détecte libmath (`-lm` dans Makefile ou symboles)

3. **Chargement du preset** :
   - Cherche exact match : `<target_name>.preset`
   - Cherche partial match : preset contenant le nom du target
   - Demande sélection interactive si ambigu
   - Utilise `default.preset` en fallback

4. **Exécution du scan** :
   - Charge la liste des fonctions du preset
   - Scanne le binaire ou les sources
   - Affiche les résultats

5. **Sortie** :
   - Exit code 0 : Aucune violation (PERFECT)
   - Exit code 1 : Au moins une violation (FAILURE)

---

### Preset par défaut

- **Emplacement** : `~/.forb/presets/default.preset`
- **Contenu initial** : Vide
- **Créé automatiquement** : Lors du premier lancement

---

### Couleurs

ForbCheck détecte automatiquement si la sortie est un terminal :

- **Terminal interactif** : Couleurs ANSI activées
- **Redirection/pipe** : Couleurs désactivées automatiquement

Les couleurs sont contrôlées par `[[ -t 1 ]]` (détection du terminal).

---

### Ordre d'exécution des flags

Bien que l'ordre soit flexible, voici la priorité interne :

1. **Aide/Version** : `-h`, `--version` (quittent immédiatement)
2. **Actions de maintenance** : `-up`, `--remove`, `-cp`, `-rp`, etc.
3. **Configuration** : `--no-auto`, `-np`, `-b`, etc.
4. **Scan** : `-s`, `<target>`, `-f`
5. **Affichage** : `--json`, `--log`, `-t`

---

## Modes d'exécution

### Mode 1 : Scan binaire standard

```bash
./forb.sh ./my_binary
```

**Workflow :**
1. Charge le binaire
2. Extrait les symboles avec `nm`
3. Compare avec la liste du preset
4. Affiche les violations

---

### Mode 2 : Scan source explicite

```bash
./forb.sh -s
```

**Workflow :**
1. Cherche les fichiers `*.c` dans le répertoire courant
2. Utilise `grep` pour chercher les appels de fonction
3. Compare avec la liste du preset
4. Affiche les violations avec numéro de ligne

---

### Mode 3 : Vérification de liste

```bash
./forb.sh -l <target>
```

**Workflow :**
1. Charge le preset du target
2. Affiche la liste
3. Quitte sans scanner

---

### Mode 4 : Édition et gestion

```bash
./forb.sh -e
./forb.sh -cp
./forb.sh -rp
```

**Workflow :**
1. Gère les presets interactivement
2. Quitte après édition

---

## Presets

### Structure d'un preset

```
# ==============================================================================
# ForbCheck Preset: my_project
# ==============================================================================
# FLAGS SPÉCIAUX (ajouter n'importe où) :
# BLACKLIST_MODE : Inverse la logique (seules les fonctions listées sont autorisées)
# ALL_MLX        : Filtre automatiquement les symboles mlx_*
# ALL_MATH       : Autorise automatiquement les fonctions math
#
# FONCTIONS (une par ligne ou séparées par espaces/virgules) :

strcpy strcat gets sprintf printf
free malloc calloc realloc
strlen strncpy memcpy memmove
```

### Flags préset

Ces flags peuvent être ajoutés **n'importe où** dans un fichier `.preset` :

#### `BLACKLIST_MODE`
- Active le mode blacklist pour ce preset
- Les fonctions listées deviennent **autorisées** (inversion)

#### `ALL_MLX`
- Filtre automatiquement les symboles MiniLibX (`mlx_*`)
- Équivalent à utiliser `-mlx` pour ce preset

#### `ALL_MATH`
- Autorise automatiquement les fonctions mathématiques
- Équivalent à utiliser `-lm` pour ce preset

### Exemple de preset complet

```
# ForbCheck Preset: so_long
# Destiné aux projets so_long (42 école)

# Flags
ALL_MLX
ALL_MATH

# Fonctions interdites
strcpy strcat gets sprintf
malloc free realloc calloc
fork exec exit system
```

---

## Cas d'usage avancés

### Intégration CI/CD

```bash
./forb.sh --json --no-auto ./build/my_binary | jq '.status'
# Output: "PERFECT" ou "FAILURE"
```

### Archivage des logs

```bash
./forb.sh --log ./binary && \
  tar czf logs_$(date +%Y%m%d).tar.gz ~/.forb/logs/
```

### Scan multi-fichier

```bash
./forb.sh -s -f main.c parser.c lexer.c -v
```

### Analyse comparative (whitelist vs blacklist)

```bash
echo "=== Whitelist mode ==="
./forb.sh ./binary

echo "=== Blacklist mode ==="
./forb.sh -b ./binary
```

---

## Gestion des erreurs

### Code d'exit

| Code | Signification |
|------|---------------|
| 0 | Succès (PERFECT ou action administrative) |
| 1 | Erreur (FAILURE, missing deps, invalid target) |

---

### Messages d'erreur courants

#### "Required command 'nm' is not installed."
**Cause** : `nm` n'est pas disponible
**Solution** : Installer binutils : `sudo apt install binutils` (Linux) ou Xcode (macOS)

#### "Error: No target specified and auto-detection is disabled (--no-auto)."
**Cause** : `--no-auto` exige un target explicite
**Solution** : `./forb.sh --no-auto <binary>` ou `./forb.sh --no-auto -s`

#### "Non-interactive environment detected."
**Cause** : Pas de terminal interactif (SSH, CI/CD)
**Solution** : Utiliser `-P <preset_name>` ou `--json`

#### "No preset found for 'project_name'."
**Cause** : Le preset n'existe pas
**Solution** : `./forb.sh -lp` pour lister, `-cp` pour créer

#### "Warning: Using 'default' preset, but it is currently empty."
**Cause** : Le preset `default` est vide
**Solution** : `./forb.sh -e` pour ajouter des fonctions

---

## Exemples pratiques

### Exemple 1 : Vérifier un projet 42

```bash
cd ~/project/
./forb.sh
# Auto-détection du binaire via Makefile
# Auto-détection du preset
# Auto-détection de MiniLibX
# Affiche les violations
```

### Exemple 2 : Scan source avec détails

```bash
./forb.sh -s -v -p -a
# Mode source, verbeux, chemins complets, toutes les occurrences
```

### Exemple 3 : Export JSON pour scripter

```bash
result=$(./forb.sh --json ./binary)
forbidden_count=$(echo "$result" | jq '.forbidden_count')
if [ "$forbidden_count" -gt 0 ]; then
    echo "Found $forbidden_count violations!"
fi
```

### Exemple 4 : Audit avec log archivé

```bash
./forb.sh --log ./binary && \
  echo "Log saved to $HOME/.forb/logs/"
```

### Exemple 5 : Créer et tester un preset

```bash
./forb.sh -cp                    # Crée "my_project"
./forb.sh ./binary               # Teste avec le nouveau preset
./forb.sh -e                     # Édite si nécessaire
```

### Exemple 6 : Blacklist pour interdire spécifiquement

```bash
# Créer un preset avec mode blacklist
./forb.sh -cp
# Ajouter : BLACKLIST_MODE
# Lister : system execve fork

# Puis tester :
./forb.sh ./binary
# Affichera UNIQUEMENT les usages de system, execve et fork (tout le reste est autorisé)
```

---

## Notes additionnelles

### Performances

- **Scan binaire** : Très rapide (quelques millisecondes)
- **Scan source** : Plus lent selon la taille du projet (secondes)
- Utilisez `-t` pour mesurer

### Limitations connues

1. **Faux positifs en source** : Les commentaires ne sont que partiellement filtrés
2. **Symboles non-liés** : Des symboles peuvent être listés sans être utilisés
3. **Macros complexes** : Désormais largement supportées (##, variadiques), mais les cas d'obfuscation extrême peuvent varier
4. **Inline functions** : Peuvent ne pas apparaître comme symboles dans le binaire

### Bonnes pratiques

1. **Utiliser des presets** : Organisez par projet
2. **Tester régulièrement** : Intégrez dans CI/CD
3. **Documenter les exceptions** : Notez pourquoi certaines fonctions sont utilisées
4. **Archiver les logs** : Pour audit

---

## Ressources

- **Dépôt GitHub** : https://github.com/Mrdolls/forbCheck
- **Issues & Support** : https://github.com/Mrdolls/forbCheck/issues

---

**Fin de la documentation**

*Cette documentation est complète pour la version 1.14.5 de ForbCheck. Les futures versions peuvent introduire des changements.*
