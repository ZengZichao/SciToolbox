import Foundation

// MARK: - ToolProvider Protocol

/// A data source provider. Each public database implements one provider.
/// Semantically equivalent to the mini-program's `createSearchPage(cfg)` factory.
protocol ToolProvider: AnyObject {
    /// Unique identifier (e.g. "uniprot")
    var id: String { get }
    /// Display name (e.g. "UniProt 蛋白质")
    var name: String { get }
    /// Category for home grouping
    var category: ToolCategory { get }
    /// SF Symbol name for the tool icon
    var iconName: String { get }
    /// Search bar placeholder text
    var placeholder: String { get }
    /// Data source attribution note
    var dataSourceNote: String { get }

    /// Optional picker options (e.g. KEGG database list, Ensembl species list)
    var pickerOptions: [PickerOption]? { get }
    /// Default picker option ID (read-only; per-window state managed by SearchScreen)
    var defaultPickerId: String? { get }

    /// Basic search (offset=0, no pagination).
    func search(query: String) async throws -> SearchResult

    /// Paginated search with picker selection. Providers that support pagination
    /// or picker-based search should override this to use `pickerId` directly
    /// (avoiding shared-instance state issues in multi-window scenarios).
    func search(query: String, offset: Int, pickerId: String?) async throws -> SearchResult

    /// Fetch detail for a specific item. `context` carries extra fields from the list item.
    func detail(id: String, context: [String: String]?) async throws -> DetailModel
}

// Default implementations
extension ToolProvider {
    var pickerOptions: [PickerOption]? { nil }
    var defaultPickerId: String? { nil }

    /// Default: delegate to basic search, ignore pagination and picker.
    func search(query: String, offset: Int, pickerId: String?) async throws -> SearchResult {
        if offset > 0 { return SearchResult(items: [], total: 0) }
        return try await search(query: query)
    }
}

// MARK: - ToolRegistry

/// Registry of all tool providers, grouped by category.
/// Equivalent to the mini-program's `constants/tools.js` + `groupedTools()`.
final class ToolRegistry: ObservableObject, @unchecked Sendable {
    static let shared = ToolRegistry()

    @Published private(set) var providers: [any ToolProvider] = []

    init() {
        registerAll()
    }

    private func registerAll() {
        // 注册所有数据源
        providers = [
            UniProtProvider(),
            PDBProvider(),
            AlphaFoldProvider(),
            PubMedProvider(),
            NCBITaxonomyProvider(),
            NCBIGeneProvider(),
            EnsemblProvider(),
            KEGGProvider(),
            GOProvider(),
            PfamProvider(),
            BacDiveProvider(),
            MGnifyProvider(),
            GBIFProvider(),
            EuropePMCProvider(),
            GTDBOfficialProvider()
        ]
    }

    /// Grouped providers by category (in defined order), only non-empty groups.
    func grouped() -> [(category: ToolCategory, items: [any ToolProvider])] {
        ToolCategory.allCases.compactMap { cat in
            let items = providers.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    func find(id: String) -> (any ToolProvider)? {
        providers.first { $0.id == id }
    }
}
