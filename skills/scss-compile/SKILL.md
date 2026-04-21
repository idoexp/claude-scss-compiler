---
name: scss-compile
description: Recompile all non-partial .scss files in the current project (or a subpath) to match the VS Code Live Sass Compiler plugin output — expanded .css + compressed .min.css with source maps, written to the parent folder of each .scss file's directory. Use after editing any .scss or _partial.scss file to keep compiled outputs in sync. Supports exclusions via .scss-compile.json or CLI flag. Reports compile errors (file + line) with a non-zero exit code.
allowed-tools: Bash
argument-hint: "[optional: subpath relative to the current project]"
---

# scss-compile

Run the bundled PowerShell compiler on the current working directory (or an optional subpath passed as `$ARGUMENTS`).

## Invocation

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/scss-compile/bin/compile-scss.ps1" -Path "$ARGUMENTS"
```

If no argument is provided, `$ARGUMENTS` is empty and the script falls back to `$PWD` (the current project root).

To pass exclusions on the command line:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/scss-compile/bin/compile-scss.ps1" -Path "$PWD" -Exclude legacy,old
```

## Behavior

- Scans recursively for `*.scss` files under the target path
- **Skips partials** (files whose name starts with `_`)
- For each remaining file, writes two outputs to the **parent folder of the file's directory** (matches Live Sass Compiler's `savePath: "~/../"` config):
  - `<name>.css` (expanded style)
  - `<name>.min.css` (compressed style)
- Generates source maps (`.css.map`, `.min.css.map`) for both
- Uses the globally installed Dart Sass CLI (`npm install -g sass`)

## Exclusions

Three layers, merged together:

1. **Built-in defaults**: `node_modules`, `.git`, `vendor`, `dist`, `build`
2. **`.scss-compile.json`** at the target path (if present):
   ```json
   {
     "exclude": ["legacy", "src/assets/css/old"]
   }
   ```
3. **`-Exclude`** CLI flag (comma-separated list)

Matching is by directory segment OR prefix path — e.g. `old` matches any folder called `old` anywhere in the tree; `www/foo/old` matches only that specific folder.

## Error handling

- If sass compilation fails, stderr contains the exact file path, line number, and error message from Dart Sass
- Exit code is non-zero on any failure — surface the error to the user verbatim rather than retrying

## When to invoke

- After editing a `.scss` file in any project (including partials, since they may be imported by multiple entry files)
- When the user asks to "recompile", "rebuild CSS", "refresh SCSS output", or similar
