import Foundation

enum CatalogService {
    static func loadBundledArtifacts() throws -> [ArtifactDefinition] {
        let directURL = Bundle.main.resourceURL?.appendingPathComponent("artifacts.json")
        let url: URL
        if let directURL, FileManager.default.fileExists(atPath: directURL.path) {
            url = directURL
        } else if let packageURL = Bundle.module.url(forResource: "artifacts", withExtension: "json") {
            url = packageURL
        } else {
            throw CatalogError.bundledCatalogMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ArtifactDefinition].self, from: data)
    }

    static func allItems() throws -> [CatalogItem] {
        try loadBundledArtifacts().map(CatalogItem.artifact)
            + TabletCatalog.all.map(CatalogItem.tablet)
    }
}
