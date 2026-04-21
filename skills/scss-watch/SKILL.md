---
name: scss-watch
description: Start Dart Sass in --watch mode for all non-partial .scss files in the current project. Replaces the VS Code Live Sass Compiler "Watch Sass" feature — recompiles expanded .css + compressed .min.css (with source maps) automatically on every save. This is a long-running process; use `/scss-compile` for one-shot recompiles instead.
allowed-tools: Bash
argument-hint: "[optional: subpath to watch]"
---

# scss-watch

Start a persistent watcher that recompiles SCSS on save. For one-shot builds use `/scss-compile`.

## Invocation

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/scss-watch/bin/watch-scss.ps1" -Path "$ARGUMENTS"
```

If no argument is passed, the script watches the current working directory.

## Behavior

- Scans the path for non-partial `.scss` files (skips `_*.scss`)
- Respects exclusions from `.scss-compile.json` at the project root (`{"exclude": ["folder", ...]}`) plus defaults (`node_modules`, `.git`, `vendor`, `dist`, `build`)
- Starts **two concurrent sass --watch processes**:
  - Expanded → `<parent-of-sass-dir>/<name>.css`
  - Compressed → `<parent-of-sass-dir>/<name>.min.css`
- Both with source maps
- Runs until Ctrl+C

Add `-ExpandedOnly` to skip the `.min.css` watcher (lighter, less console noise during dev).

## When to use

- User asks to "watch SCSS", "live compile", "auto-recompile", "watch mode"
- User wants to replace the VS Code Live Sass Compiler plugin entirely

## Notes

- This is a **long-running process** — once started it blocks until stopped
- Do NOT invoke automatically; only when the user explicitly requests watch mode
- For routine recompile-after-edit, prefer `/scss-compile` (one-shot, returns immediately)
