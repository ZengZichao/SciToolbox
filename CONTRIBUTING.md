# Contributing to SciToolbox

Thanks for your interest. SciToolbox is a native SwiftUI macOS app that aggregates public academic databases into a single search interface. It is released under GPL-3.0.

## Development setup

- macOS 15.0+ and Xcode (full) or a Swift 6.0+ toolchain.
- Clone, then run:
  ```bash
  ./run.sh run            # debug run
  swift build             # manual build
  swift test              # requires full Xcode (XCTest)
  ```

## Project layout

See `README.md` (中文) and `README_EN.md` for the full architecture. Key entry points:

- `Sources/SciToolbox/Providers/` — one file per data source, conforming to `ToolProvider`.
- `ToolRegistry.swift` — registers providers and groups them by category.
- `Models.swift` — shared `ResultItem` / `DetailModel` / `KVSection`.
- `APIClient.swift` — unified HTTP layer (timeout / retry / throttling).

## Adding a new data source

1. Create `Sources/SciToolbox/Providers/<Name>Provider.swift` conforming to `ToolProvider` (`search` + `detail`).
2. Register it in `ToolRegistry` and assign a category color in `Theme.swift`.
3. Add a fixture JSON under `Tests/SciToolboxTests/Fixtures/` and a parse test in `ParseTests.swift` — this guards against upstream schema changes.
4. Verify the source's terms of use and add an entry to `COMPLIANCE.md`.

## Code style

- Swift 6, language mode v5 (see `Package.swift`).
- Keep providers thin: all networking via `APIClient`, parsing isolated, no UI inside providers.
- Respect upstream rate limits (see `COMPLIANCE.md`); NCBI E-utilities enforce a ≥3s minimum interval via `RequestThrottle`.

## Pull requests

- Keep PRs focused and describe the data source / behavior change.
- Ensure `swift test` passes.
- By contributing, you agree your contributions are licensed under GPL-3.0.

## Support expectations

SciToolbox began as a personal research utility and is maintained on a **best-effort** basis. We aim to keep it building and to respond to issues, but do not guarantee timely fixes or feature work. Pull requests are welcome and appreciated.

## Reporting issues

Use the issue templates. For security issues, follow `SECURITY.md` (do **not** open a public issue).
