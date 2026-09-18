# Roadmap

SciToolbox is a personal research tool released under GPL-3.0. Directions below are indicative and may change based on feedback.

## Near term

- Additional providers (e.g., ENA, Reactome, DisProt).
- Improved cross-database entity resolution — the current router is regex-based with confidence scoring.
- Better empty/error-state guidance per data source.

## Mid term

- Saved searches / lightweight alerting.
- Plugin-style provider registration so contributors can add sources without modifying core.

## Exploratory (no commitment)

- A reusable Swift package extracting the `Provider` + `APIClient` layer for other academic tools.
- Broader platform reach beyond macOS (currently SwiftUI / macOS 15+ only).

Feedback and priorities are welcome via the issue tracker.
