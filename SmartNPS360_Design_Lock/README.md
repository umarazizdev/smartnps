# SmartNPS360 design lock

1. Extract this folder into your local project's root (or place it beside it) as `SmartNPS360_Design_Lock`.
2. Open that project in Codex and paste `CODEX_PROMPT.md`, pointing Codex at this folder.
3. Let Codex inspect the project and integrate the token file and assets; do not blindly replace controllers.

The two reference PNGs are the user's final approved generated light/dark mockups. The 143 fixed paired widget-color tokens use representative raster samples and authored complementary values; 82 geometry tokens, explicit gradients, shadows and absent-state styling are implementation decisions rather than recovered original design-layer metadata. All four SVGs and both PNG empty-state assets are copied unchanged from the earlier generated packages. JSON lists literal SVG colors, gradient stops and file checksums. The Dart file is a standalone theme helper, not a replacement application. It has not been compiled or checked by Flutter Analyzer in this environment. Actual visual comparison and integration must be performed against the local app.
