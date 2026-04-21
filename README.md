# claude-scss-compiler

Un bundle portable de **skills Claude Code** qui remplace l'extension VS Code **Live Sass Compiler**. Une fois installé, Claude peut recompiler le SCSS de votre projet tout seul pendant l'itération, et vous pouvez le déclencher manuellement avec `/scss-compile` ou `/scss-watch`.

## Skills inclus

| Skill           | Rôle                                                                      |
|-----------------|---------------------------------------------------------------------------|
| `/scss-compile` | Recompile en une passe tous les fichiers `.scss` non-partials (expanded + min + source maps). |
| `/scss-watch`   | Lance un `sass --watch` long-running qui recompile à chaque sauvegarde (remplace le "Watch Sass" de Live Sass Compiler). |

Les deux écrivent dans le **dossier parent** du répertoire du `.scss` — identique au paramètre `savePath: "~/../"` de Live Sass Compiler.

## Installation (one-click)

1. Cloner le dépôt à l'emplacement de votre choix :

   ```bash
   git clone https://github.com/idoexp/claude-scss-compiler.git
   cd claude-scss-compiler
   ```

2. Lancer l'installeur depuis PowerShell :

   ```powershell
   .\install.ps1
   ```

L'installeur vérifie / installe automatiquement :

| Vérification     | Action si absent                                 |
|------------------|--------------------------------------------------|
| PowerShell 5.1+  | Échoue avec lien d'install (rare sur Windows 10+) |
| Claude Code      | Échoue avec lien d'install                       |
| Node.js LTS      | `winget install OpenJS.NodeJS.LTS`               |
| npm              | Fourni avec Node                                 |
| Dart Sass ≥ 1.70 | `npm install -g sass`                            |

Il déploie ensuite chaque dossier de `skills/` dans `~/.claude/skills/<nom>/` et lance un self-test sur `scss-compile`.

**Réinstaller sans confirmation :** `.\install.ps1 -Force`

## Utilisation

Après installation, **redémarrer Claude Code**. Puis :

### `/scss-compile` (recompile one-shot)

```text
/scss-compile                     # recompile tout le projet courant
/scss-compile src/assets/css      # recompile uniquement ce sous-arbre
```

Claude appelle aussi ce skill tout seul après édition d'un `.scss`, pour garder les sorties à jour.

### `/scss-watch` (recompile auto en live)

```text
/scss-watch           # démarre le watcher sur le projet courant
/scss-watch src/scss  # watch uniquement un sous-arbre
```

Lance deux processus `sass --watch` en parallèle (expanded + compressed). **Ctrl+C** pour arrêter.

## Config par projet

Déposer un fichier `.scss-compile.json` à la racine du projet pour personnaliser le comportement :

```json
{
  "exclude": [
    "legacy",
    "src/assets/css/old"
  ]
}
```

### Règles d'exclusion

Trois couches fusionnées :

1. **Exclusions par défaut** — `node_modules`, `.git`, `vendor`, `dist`, `build`
2. **Tableau `exclude`** de `.scss-compile.json`
3. **Flag CLI** `-Exclude foo,bar` (avancé — les skills passent `$ARGUMENTS`, donc la couche 2 suffit en général)

Le matching se fait par :
- **Segment de dossier n'importe où** — `old` exclut tout dossier appelé `old` à toute profondeur
- **Chemin préfixe exact** — `src/css/old` exclut uniquement ce dossier précis

Claude peut éditer ce fichier pour vous : dites *"ajoute le dossier X aux exclusions SCSS"* et il mettra `.scss-compile.json` à jour.

## Gestion d'erreurs

Les erreurs de compilation **ne sont pas** avalées silencieusement. Si un `.scss` échoue :

- Le stderr de Dart Sass est affiché tel quel (fichier, ligne, colonne, message)
- Le code de sortie est non-zéro
- Le skill remonte l'erreur à vous / à Claude au lieu d'échouer en silence

## Désinstallation

```powershell
Remove-Item -Recurse $HOME\.claude\skills\scss-compile
Remove-Item -Recurse $HOME\.claude\skills\scss-watch
npm uninstall -g sass   # optionnel — seulement si vous n'utilisez plus sass ailleurs
```

## Dépannage

**`cannot be loaded because running scripts is disabled on this system`**
Lancer l'installeur avec bypass explicite :
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

**`winget` introuvable**
Installer Node.js LTS manuellement depuis <https://nodejs.org/> puis relancer l'installeur.

**`npm install -g sass` échoue avec une erreur de permission**
Lancer PowerShell en Administrateur, ou configurer `npm config set prefix` vers un dossier accessible à l'utilisateur avant de retenter.

**Le skill n'apparaît pas dans Claude Code**
Quitter complètement Claude Code et le relancer (les skills sont chargés au démarrage). Vérifier avec :
```powershell
Test-Path "$HOME\.claude\skills\scss-compile\SKILL.md"
Test-Path "$HOME\.claude\skills\scss-watch\SKILL.md"
```

## Structure

```
claude-scss-compiler/
├── install.ps1                         # installeur one-click
├── skills/
│   ├── scss-compile/
│   │   ├── SKILL.md
│   │   └── bin/compile-scss.ps1
│   └── scss-watch/
│       ├── SKILL.md
│       └── bin/watch-scss.ps1
└── README.md
```

## Licence

MIT — voir [LICENSE](LICENSE).
