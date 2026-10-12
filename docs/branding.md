# Runner yellow artwork

The iPhone/iPad app and photo sticker use the existing running figure in yellow on black. The Watch artwork remains unchanged.

The built-in imagegen tool edited the original iOS icon, then the result was normalized to an opaque 1024×1024 sRGB PNG and installed in both named assets:

- `Runner: Analyzer & Tracking/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- `Runner: Analyzer & Tracking/RunPhotoAssets.xcassets/RunPhotoAppIcon.imageset/AppIcon.png`

Generation prompt: “Change only the colors of the existing app icon: blue background to solid black #000000; white runner to sporty yellow #D7FF00. Preserve the runner silhouette, pose, head circle, limb shapes, rounded edges, rear-leg gap, proportions, position, and margins. Use flat, opaque, crisp artwork without added symbols, branding, text, texture, glow, or borders.”

The interface and photo wordmark use exact fixed sRGB `#D7FF00`. The generated raster icon has antialiasing and small pixel-level color variation. Its rendering test checks dimensions, opacity, a substantial yellow silhouette, and a mostly black background.
