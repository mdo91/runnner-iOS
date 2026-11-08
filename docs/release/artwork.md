# Runner release artwork

The six onboarding illustrations were generated with the built-in `image_gen` tool on November 8, 2026. No API/CLI fallback was used. The original outputs are preserved; their PNGs are copied unchanged into `Runner: Analyzer & Tracking/OnboardingAssets.xcassets` for the application and website to reuse. All artwork is text-free so English and German copy can remain native, accessible, and editable.

## Asset names

- `OnboardingWelcome`: a joyful runner in motion, with a curved running track.
- `OnboardingHealth`: a runner presenting a phone that brings running records together.
- `OnboardingInsights`: a runner studying pace, heart-rate, and route panels.
- `OnboardingProgress`: a runner moving up steps beneath a progress line.
- `OnboardingShare`: a runner holding a shareable run image, with a video symbol.
- `OnboardingPrivacy`: a runner protecting a heart beside a shield and privacy choices.

Each image set contains `Artwork.png` and a universal `Contents.json`. Preserve the PNG alpha channel when reusing these illustrations. They are intended to be placed on the app's near-black background; cream and yellow fills keep the figures legible there. The phone and chart shapes are explanatory illustrations, not fabricated app screenshots.

## First illustration prompt

Use case: illustration-story. Asset type: square mobile onboarding illustration for Runner, an adult running analytics app, also reusable on its website. Create a crisp contemporary editorial cartoon of one joyful athletic runner mid-stride, expressive elastic pose, confident relaxed face, chunky running shoes and flying shoelaces. A few loose hand-drawn motion marks and curving track lines support the motion. Palette: electric yellow #D7FF00, near-black #0B0B0B, soft cream #F5F2E8, restrained cool gray. Style: bold uneven ink outlines, flat filled shapes, subtle paper-grain sparingly, sophisticated sporty doodle art, no gradients, no 3D, not childish. Composition: one complete scene centered in a square, full body visible, generous clear margins, no crop, will sit on a dark black app background. Real transparent background; make dark outlines visible with cream/yellow fill and highlights. No text, no letters, no numbers, no logos, no watermark. This is the first illustration in a cohesive set about understanding every run.

## Shared prompt for the five accompanying illustrations

The first illustration was supplied as a **style reference**, not an edit target. Each accompanying illustration was a separate generation with `transparent_background: true`.

Use case: illustration-story. Asset type: a square illustration for Runner app onboarding and public marketing website. The input image is a STYLE REFERENCE only, not an edit target: create a NEW scene with the same contemporary sporty editorial cartoon language, bold uneven ink outlines, elastic expressive adult runners, oversized running shoes, flat filled shapes and restrained grain. Palette electric yellow #D7FF00, near-black #0B0B0B, soft cream #F5F2E8, cool gray, natural skin tones. Authentic transparent background to sit on a dark app; use cream/yellow areas so the figure reads on black. Square composition, entire scene inside frame, generous breathing room. No text, letters, numerals, logos or watermarks. No gradient, 3D, branding, or UI words.

### Health scene

An adult runner with warm brown skin and a yellow athletic outfit stands beside a large simplified cream smartphone; a yellow heart floats above the phone. Three small abstract running-track ribbons converge gently into it. The runner looks pleased and gestures toward their runs being together. Show only simple visual icons inside the phone, no detailed invented app interface.

### Insights scene

An adult runner with short dark hair leans forward curiously toward three floating cream mini-panels: a simple pace line graph, a yellow heart with one pulse stroke, and a looping route with dots. The runner is in a natural crouched athletic stance, inspecting the visual patterns. Keep panels simple and legible, no text or numbers, no axes labels. Hand-drawn arrows connect observations.

### Progress scene

An upbeat adult woman runner with dark skin and yellow shoes moves up three chunky cream and gray ascending steps, with a gently rising yellow line above them and three small celebratory doodle stars. Convey steady progress and consistency, not a race win or guaranteed result. Strong diagonal composition with full body inside frame.

### Sharing scene

An adult runner in black and yellow sportswear cheerfully holds a large cream picture frame at their side. The frame contains a tiny running silhouette, a simple route squiggle and three plain statistic-like bars without text or numbers. A separate small yellow play triangle badge implies video. Hand-drawn sparkles and one curved arrow convey sharing a finished run. Full body visible.

### Privacy scene

A calm confident adult runner with curly hair and a yellow jacket sits beside a large cream shield, gently holding a yellow heart close. Three simple small toggles float nearby, with one on and two off, illustrating personal choice. The shield has a simple black check shape. Friendly reassuring posture, not cybersecurity drama. Full character and shield clearly inside square.

## Validation

The generated scenes were visually reviewed for the requested theme, coordinated palette, complete character composition, and absence of text or branding. All six installed files are 1254 × 1254 RGBA PNGs with transparency; all image-set JSON references resolve to their files. Their combined PNG file size is approximately 7.65 MB. App and website layout checks remain part of release validation.

## Synthetic editor photograph

`docs/release/assets/runner-editor-photo.png` is an original, fictional runner photograph generated with the built-in `image_gen` tool on November 8, 2026, with `transparent_background: false`. It is available for the real app editor's screenshot fixture and the public website. The original 1536 × 1024 PNG is copied unchanged. Visual inspection confirmed a complete central runner, believable running posture, room for overlays in the top-left, and no text, logos, other people, or identifying landmarks. The scene and person are synthetic; no private user photograph or real workout is used.

### Photograph prompt

Use case: photorealistic-natural. Asset type: privacy-safe synthetic editorial sports photograph for a running app's photo-editor screenshot and public website. Create a fictional adult runner in their early thirties, fit everyday amateur athlete, mid-stride running on a quiet empty park path beside a simple athletics track at dawn. Natural candid sports photography, believable anatomy and foot placement, documentary realism, subtle movement in clothes, clear subject, soft warm early sunlight, calm muted green trees in background. The runner wears an unbranded electric-yellow sleeveless running top and plain black shorts with neutral shoes. Landscape 3:2 composition, ideally 1536x1024. Keep the entire runner comfortably inside the central third so a portrait or square crop still works. Leave the top-left quadrant mostly uncluttered sky/soft foliage so a real app can place running-stat text there later. No text or numbers in the image itself. No logos, race bibs, signs, distinctive buildings or identifying landmarks. No other people. No phone mockup, no interface, no added stats, no watermarks. This must be a newly generated fictional person and scene, not a photograph of a known person. Opaque photographic background.

## App Store layouts

`scripts/render-store-screenshots.swift` renders eight genuine app captures per language with localized headlines, reusable illustrations, scribbles, and track patterns. Capture input filenames and copy are defined in `screenshot-copy.json`. All exports are opaque RGB PNGs.

- Large Dynamic Island slot: `screenshots/{en,de}`, 1320 × 2868.
- Required medium Dynamic Island slot: `screenshots-medium/{en,de}`, 1206 × 2622, generated with `--display medium`.

App Store Connect accepted both sets on November 8, 2026. Each locale has eight screenshots in each slot and no video previews. Layouts use a shared design coordinate system with uniform scaling; the actual app captures are not stretched or fabricated.

## Product-page header and search results

Added November 8, 2026. The shared text-free header is `creative-assets/header.png` (3840 × 1646). Localized search-result layouts are `creative-assets/search-en.png` and `creative-assets/search-de.png` (1920 × 1280). These are opaque RGB PNGs, separate from screenshots and video previews, for the creative placements on iOS 27 and later.

The header was generated using the built-in `image_gen` tool, with the existing welcome runner as a style reference; no CLI/API fallback was used. Its original 1832 × 858 output is preserved as `creative-assets/header-source.png`. The export fits the complete original illustration proportionally inside Apple's required dimensions. The search layouts reuse the original onboarding artwork and unchanged genuine synthetic-data captures from the passing screenshot run `20261108-162338-25472.xcresult`; copies are preserved in `creative-assets/sources`.

`scripts/render-store-creative.swift` reproducibly composes the layouts and verifies exact dimensions and absence of alpha. It does not invent or retouch the app interface. English copy is “Every run. Understood.” / “Pace. Heart rate. Progress.” German is “Jeder Lauf. Im Blick.” / “Tempo. Puls. Fortschritt.”

### Header prompt

Use case: ads-marketing. Asset type: App Store product-page header artwork for Runner, a running analytics and photo/video sharing app. Generate one finished premium editorial illustration, opaque, wide cinematic 21:9 landscape, target 3840 × 1646 pixels. Existing Runner onboarding illustration is a style reference only. Match its expressive adult runner, bold uneven ink outlines, electric yellow #D7FF00, cream #F5F2E8, near-black #0B0B0B, warm natural skin, restrained hand-drawn grain. One joyful athletic adult woman mid-stride, full body visible, black/yellow running outfit and cream chunky shoes. Center the complete runner within the middle 45 percent, broad quiet near-black margins and safe cropping room. A cream/yellow running-track ribbon becomes one expressive pace-chart line and a small looping route motif, with a small yellow heart. Sparse illustrative symbols; no interface panels or phone mockup. One clear focal point, energetic and confident, polished flat illustration, strong contrast, subtle charcoal track arcs. No gradients, photorealism, 3D, words, letters, numbers, logos, watermarks, copyright marks, prices, awards, badges, Apple branding, or medical promise. Text-free for both English and German.

Specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
Best practices: https://developer.apple.com/app-store/asset-best-practices/
