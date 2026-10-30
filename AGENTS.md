# Press shaders

The shader library for Press (`nexis-suite/nexis-press/`). Press reads `index.json` from this repo's `main` and installs, updates and removes shaders from it. Public.

Workspace rules live in `Dev/AGENTS.md`.

## Format

A shader is **data, not code**: `shaders/<name>/shader.json` (name, version, category, controls) plus `shader.glsl` (the fragment body). Nothing here runs as JavaScript. Keep it that way.

## Rules

- Adding or changing a shader means updating `index.json` in the same change, and bumping the shader's `version`.
- Pushing to `main` publishes to every Press install. Do not push without being asked.
- Banknote Engraving also ships inside Press for offline use; keep the two in sync.
- Check `shader.glsl` compiles in Press before publishing; a broken shader draws wrong or fails to compile.

## Layout

| Path | What lives there |
|---|---|
| `index.json` | Catalog Press reads |
| `shaders/` | One folder per shader |
