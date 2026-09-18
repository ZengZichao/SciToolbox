import XCTest
import Foundation
@testable import SciToolbox

/// Parse tests for key providers. Each test loads a sample JSON fixture
/// and validates that the parsing logic produces expected output.
/// If an upstream API changes its schema, these tests will break —
/// serving as an early warning system.
final class ParseTests: XCTestCase {

    // MARK: - UniProt Search Parse Test

    func testUniProtSearchParse() throws {
        let parsed = try parseFixture("uniprot_search.json")

        let results = parsed["results"].arrayValue
        XCTAssertFalse(results.isEmpty, "UniProt search should return results")

        let first = results[0]
        let accession = first["primaryAccession"].string
        XCTAssertNotNil(accession, "primaryAccession should exist")
        XCTAssertFalse(accession!.isEmpty, "accession should not be empty")

        let proteinName = UniProtProvider.proteinName(of: first)
        XCTAssertFalse(proteinName.isEmpty, "protein name should be parsed")

        let length = first["sequence"]["length"].int
        XCTAssertNotNil(length, "sequence length should exist")
        XCTAssertTrue(length! > 0, "sequence length should be positive")
    }

    // MARK: - PubMed Search Parse Test

    func testPubMedSearchParse() throws {
        let parsed = try parseFixture("pubmed_search.json")

        let idlist = parsed["esearchresult"]["idlist"].arrayValue
        XCTAssertFalse(idlist.isEmpty, "PubMed search should return PMIDs")

        // NCBI esearch 的 count 是字符串（如 "15234"）
        let countNode = parsed["esearchresult"]["count"]
        let total = countNode.int ?? Int(countNode.string ?? "") ?? -1
        XCTAssertTrue(total > 0, "total count should be positive")

        let firstId = idlist[0].string
        XCTAssertNotNil(firstId, "first PMID should be a string")
    }

    // MARK: - PDB Search Parse Test

    func testPDBSearchParse() throws {
        let parsed = try parseFixture("pdb_search.json")

        let resultSet = parsed["result_set"].arrayValue
        XCTAssertFalse(resultSet.isEmpty, "PDB search should return results")

        let totalCount = parsed["total_count"].int
        XCTAssertNotNil(totalCount, "PDB search should return total_count")
        XCTAssertTrue(totalCount! > 0, "total_count should be positive")

        let firstId = resultSet[0]["identifier"].string
        XCTAssertNotNil(firstId, "first result should have identifier")
        XCTAssertEqual(firstId?.count, 4, "PDB ID should be 4 characters")
    }

    // MARK: - GTDB Detail Parse Test

    func testGTDBDetailParse() throws {
        let parsed = try parseFixture("gtdb_detail.json")

        let children = parsed.arrayValue
        XCTAssertFalse(children.isEmpty, "GTDB detail should return children array")

        let firstChild = children[0]
        let taxon = firstChild["taxon"].string
        XCTAssertNotNil(taxon, "child should have taxon field")
        XCTAssertFalse(taxon!.isEmpty, "taxon should not be empty")

        // Verify taxon format contains rank separator
        XCTAssertTrue(taxon!.contains("__"), "taxon should contain rank separator '__'")
    }

    // MARK: - UniProt Detail Parse Test

    func testUniProtDetailParse() throws {
        let parsed = try parseFixture("uniprot_detail.json")

        let accession = parsed["primaryAccession"].string
        XCTAssertNotNil(accession, "UniProt detail should have primaryAccession")

        let organism = parsed["organism"]["scientificName"].string
        XCTAssertNotNil(organism, "UniProt detail should have organism scientificName")

        let sequence = parsed["sequence"]["value"].string
        XCTAssertNotNil(sequence, "UniProt detail should have sequence value")
        XCTAssertFalse(sequence!.isEmpty, "sequence should not be empty")

        // Check dbReferences exist (for xlinks)
        let dbRefs = parsed["dbReferences"].arrayValue
        XCTAssertFalse(dbRefs.isEmpty, "UniProt detail should have dbReferences")
    }

    // MARK: - PDB Entry Parse Test

    func testPDBEntryParse() throws {
        let parsed = try parseFixture("pdb_entry.json")

        let entryId = parsed["entry"]["id"].string
        XCTAssertNotNil(entryId, "PDB entry should have id")

        let title = parsed["struct"]["title"].string
        XCTAssertNotNil(title, "PDB entry should have struct.title")

        let methods = parsed["rcsb_entry_info"]["experimental_method"].string
            ?? parsed["exptl"].arrayValue.first?["method"].string
        XCTAssertNotNil(methods, "PDB entry should have experimental method")

        let entityCount = parsed["rcsb_entry_info"]["entity_count"].int
        XCTAssertNotNil(entityCount, "PDB entry should have entity_count")
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> Data {
        // SwiftPM 资源放在独立的 *_Tests.bundle 中，Bundle(for:) 拿不到；Bundle.module 指向它
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle(for: ParseTests.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle(for: ParseTests.self).url(forResource: name, withExtension: nil)
        guard let url = url else {
            throw XCTestError(.failureWhileWaiting)   // fixture 缺失属测试基础设施故障，显式失败而非静默跳过
        }
        return try Data(contentsOf: url)
    }

    /// JSON(json) 是可失败构造器，直接解析得到 JSON?——测试中统一强制解包（fixture 存在性已由 loadFixture 保证）。
    private func parseFixture(_ name: String) throws -> JSON {
        guard let parsed = JSON(try loadFixture(name)) else {
            throw XCTestError(.failureWhileWaiting)
        }
        return parsed
    }
}
