# SciToolbox — macOS Research Data Toolbox

> A native SwiftUI macOS app that aggregates 15 public academic databases into a single search interface.
> Open-source research utility. No login, no collection of any user personal data.

## Features

### 15+ data sources

| Category | Tool | Source |
| --- | --- | --- |
| Taxonomy & species | GTDB official taxonomy | gtdb-api.ecogenomic.org |
| Taxonomy & species | NCBI Taxonomy | eutils.ncbi.nlm.nih.gov |
| Taxonomy & species | BacDive strains | api.bacdive.dsmz.de |
| Taxonomy & species | MGnify metagenomics | www.ebi.ac.uk/metagenomics |
| Taxonomy & species | GBIF species | api.gbif.org |
| Gene & sequence | NCBI Gene / Sequence | eutils.ncbi.nlm.nih.gov |
| Gene & sequence | Ensembl | rest.ensembl.org |
| Protein & structure | UniProt | rest.uniprot.org |
| Protein & structure | RCSB PDB | data.rcsb.org |
| Protein & structure | AlphaFold | alphafold.ebi.ac.uk |
| Protein & structure | Pfam / InterPro | www.ebi.ac.uk/interpro |
| Function & pathway | KEGG | rest.kegg.jp |
| Function & pathway | GO terms | www.ebi.ac.uk/QuickGO |
| Literature | PubMed | eutils.ncbi.nlm.nih.gov |
| Literature | Europe PMC | www.ebi.ac.uk/europepmc |

### Highlights

- **Three-pane layout** (sidebar → search + results → detail), each pane resizable.
- **⌘K command palette** to jump to any tool, with `tool:query` syntax.
- **Full-library parallel search** — one keyword across all databases, grouped by category.
- **Cross-database linking** (UniProt ↔ PDB / Pfam / GO / PubMed / Ensembl / AlphaFold, etc.).
- **Accession intelligent router** — paste a UniProt / PDB / gene symbol / DOI / GO / ENS / PF / K / TaxID and it routes to the right database.
- **Local-first**: query history, favorites, and project collections stored locally (UserDefaults), exportable as text/JSON/CSV.
- **Project collections (1.0.0)**: organize related entries into projects with per-entry notes, batch verify/refetch against latest upstream data, and CSV/JSON export.
- **Direct HTTPS** to public APIs — no cloud proxy, no account, no telemetry.
- **Accessibility**: dark mode, WCAG AA contrast, VoiceOver labels, respects Reduce Motion.
- **Bilingual UI (Chinese / English)**: switch between 中文 and English from Settings; all interface text, relative timestamps, and accessibility labels are localized instantly and persisted across sessions.

## Requirements

- macOS 15.0+
- Swift 6.0+
- Running tests requires full Xcode (command-line tools lack XCTest)

## Build & Run

```bash
# Quick start (debug run)
./run.sh run

# Manual build
swift build
swift run SciToolbox
swift build -c release

# Package as a .app
./run.sh app          # produces build/SciToolbox.app
./run.sh install      # install to /Applications
```

## Tests

Sample-JSON fixtures guard against upstream API schema changes.

```bash
swift test            # requires full Xcode
```

## Architecture

See the Chinese `README.md` for the full architecture, design system, and compliance statement.

## Compliance

- No account, no personal-data collection.
- Query history and favorites are stored locally only and can be cleared or exported at any time.
- Cache stores request→response only, with no user/device identifiers.
- Public content only; "data source" attribution preserved.
- Complies with each upstream API's terms of use, rate limits, and attribution requirements.

## License

GPL-3.0. See [LICENSE](LICENSE).
