# Press shaders

The shader library for [Press](https://github.com/rwetz/nexis-press). Press
reads `index.json` from this repository's `main` branch, and installs,
updates and removes shaders from it. Banknote Engraving also ships inside
Press, so Press works offline.

A shader is data, not code: `shader.json` (its name, version, category and
controls) plus `shader.glsl` (the fragment body). Nothing here runs as
JavaScript. The worst a broken shader can do is draw wrong or fail to
compile.

## Layout

```
index.json                       every shader, its newest version and where it is
shaders/<id>/<version>/
  shader.json                    the manifest
  shader.glsl                    the fragment body
```

Each version gets its own folder and is never edited after it's published.
To release a new version, add a folder and point the shader's entry in
`index.json` at it.

## index.json

```json
{
  "format": 1,
  "shaders": [
    { "id": "banknote", "name": "Banknote Engraving", "version": "1.0.0", "category": "Print",
      "description": "…", "path": "shaders/banknote/1.0.0", "host": 1 }
  ]
}
```

`host` is the version of Press's shader header that the shader needs. A
Press that's too old leaves the shader out of the list.

## Writing a shader

The manifest format and the uniforms that the host provides are documented in
Press: `src/core/shader.ts` and the README's "Adding a shader".
`shaders/banknote/1.0.0` is a full example. Press checks every manifest when
it installs a shader and shows what's wrong. The `id` and `version` in
`shader.json` must match the shader's entry in the index.

To try a library before publishing it, serve this folder over HTTP with CORS
and set Press's library address (Settings, Shader library) to it.
