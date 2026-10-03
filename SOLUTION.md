# Build path notes

The shared project is `The Runner.xcodeproj`; use scheme `The Runner`. The app's existing display/product name remains Runner: Analyzer & Tracking.

Some command-line tools treat a colon in the checkout path as a path separator. Quote all paths and use a DerivedData directory outside the checkout if necessary. The separate backend invokes its TypeScript tools through Node explicitly for this reason.

See [README.md](README.md) for current setup, tests, privacy behavior, and device release checks.
