# Dashboard design lock integration

Implemented from `SmartNPS360_Design_Lock/CODEX_PROMPT.md`, the supplied Dart tokens, JSON, approved references, and unchanged artwork. The package is retained at the project root for review.

## Files

- `lib/src/screens/new_screens/Dashboard/theme/dashboard_design_tokens.dart`: supplied palette and geometry helper.
- `lib/src/screens/new_screens/Dashboard/new_dashboard_screen.dart`: greeting, action buttons, statistics, responsive shortcut cells and category palettes.
- `lib/src/screens/new_screens/Dashboard/new_dashboard_hero.dart`: SVG background, real segmented dial, fixed top marker, status pill, footer and approved empty-state assets/contact links.
- `lib/src/screens/new_screens/Widgets/new_app_header.dart`: palette-driven controls and brand; existing logo, icons, theme toggle and notification action retained.
- `lib/src/screens/new_screens/new_main_screen.dart`: page gradient and clipped theme-specific header artwork.
- Bottom navigation restored to its previous implementation at the user's request. Its layout, platform behavior and original colors remain unchanged; package colors apply to the dashboard content and header.
- Six original package images copied into `assets/images/`. Existing directory registration and dependencies already cover them. All six SHA-256 checks matched the package JSON.
- `test/dashboard_design_lock_test.dart`: isolated fixtures and screenshot capture; no fixture data added to production controllers.

## Verification

- `flutter analyze`: no issues.
- `flutter test test/dashboard_design_lock_test.dart --reporter expanded`: 14 tests passed.
- Both themes at 390 × 844; upcoming, late, working, working after late arrival, break, standby and no assigned shift. Screenshots are in `screenshots/`.
- Each case also lays out at 320 × 700 with 1.4 text scaling without a rendering exception. Shortcut row height expands with text size.
- Approved empty PNGs are decoded before capture. Existing PTSans and MaterialIcons fonts are loaded in the test renderer.
- Existing controllers, session state, timers, schedule calculations, auth/API integration and action callbacks were not edited. WhatsApp and telephone targets remain `https://wa.me/14158004372` and `tel:+14158004372`.
- Light stat samples matched fixed tokens exactly: warning top/bottom `#FEECEF` / `#FEECEE`; on-time top/bottom `#E9F8F3` / `#E8F9F3`. Dark samples near the ends of gradients were within 1–3 RGB levels of endpoint tokens, as expected inside an interpolated gradient.
- Hero crop overlays and absolute difference images compare app card content only, normalized to the same crop size. They are visual diagnostics, not a pixel-perfect score.

## Remaining differences and limits

- This is not pixel-perfect to the generated raster references. The existing PTSans font, real NPS seal and original icon assets differ from the generated artwork. The extra theme switch is retained as required.
- The fixed token dimensions and raster proportions are not identical. The hero grows to accommodate its 208 dp dial, header and footer instead of forcing the separately supplied 250 dp card height and overlapping content. The 154 dp header artwork is partly covered by the following card in this compact shell.
- All configured shortcuts remain; the reference shows only three. The lower rows are scrollable behind the safe-area-aware navigation with bottom content padding.
- Accessible warning/active label colors are used for small text. No supplied artwork was tinted or modified.
- Fixtures validate rendering, not live backend transitions, GPS, permissions, background/resume, completed/error/loading API states or device-native integrations. Those still need a device session with real account data. The pre-existing controller's sample bootstrap logic remains unchanged.
- No before screenshot of the running application was available; the package references provide the comparison target. No phone frame or simulated OS chrome was added.
