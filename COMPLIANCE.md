# Data Source Compliance

SciToolbox is a read-only client for **public** academic databases. It bundles no API keys, sends no user data, and stores nothing remotely. This document records, per source, the attribution / terms posture so contributors can verify compliance. **Terms change — re-verify each source before publishing and keep this table current.**

| Source | Endpoint | Attribution / terms note |
| --- | --- | --- |
| GTDB | gtdb-api.ecogenomic.org | Cite GTDB; public API |
| NCBI E-utilities (Taxonomy / Gene / PubMed) | eutils.ncbi.nlm.nih.gov | Cite NCBI; ≥3s request interval enforced (`RequestThrottle`); rate-limited |
| BacDive | api.bacdive.dsmz.de | Cite DSMZ / BacDive |
| MGnify | www.ebi.ac.uk/metagenomics | Cite EBI MGnify |
| GBIF | api.gbif.org | Cite GBIF |
| UniProt | rest.uniprot.org | Cite UniProt |
| Ensembl | rest.ensembl.org | Cite Ensembl |
| RCSB PDB | data.rcsb.org | Cite RCSB PDB |
| AlphaFold | alphafold.ebi.ac.uk | Cite EMBL-EBI / AlphaFold DB |
| Pfam / InterPro | www.ebi.ac.uk/interpro | Cite InterPro / EBI |
| KEGG | rest.kegg.jp | Public REST API intended for academic / non-commercial use; cite KEGG. **Commercial use requires a KEGG license — verify before any commercial or high-volume use.** |
| GO / QuickGO | www.ebi.ac.uk/QuickGO | Cite GO Consortium |
| Europe PMC | www.ebi.ac.uk/europepmc | Cite Europe PMC / PubMed |

## General rules

- No API keys are bundled; every endpoint is public.
- NCBI E-utilities: a ≥3s minimum request interval is enforced to avoid HTTP 429.
- Respect each source's rate limit and terms of use; no bulk scraping.
- KEGG: academic / non-commercial use of its public REST API is permitted; commercial use requires a KEGG license — confirm before any commercial deployment.

## Maintainer action

Before making the repository public, confirm each source's current terms of use and update this table. If a source's terms forbid redistribution of client code or derived data, either remove that provider or document the restriction prominently.
