import Foundation

enum ItemKind: String, Codable, Sendable {
    case artifact
    case tablet
}

struct ArtifactDefinition: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let value: String
    let labelKorean: String
    let labelEnglish: String
    let tier: String
    let imageURL: URL
    let capacity: Int

    enum CodingKeys: String, CodingKey {
        case id, value, tier
        case labelKorean = "label_kor"
        case labelEnglish = "label_eng"
        case imageURL = "image"
        case capacity = "level"
    }
}

struct TabletDefinition: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let koreanName: String
    let tier: String
    let imagePath: String
    let isRotatable: Bool

    var imageURL: URL {
        let path = imagePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://img.sephiria.wiki/\(path)")!
    }
}

enum CatalogItem: Identifiable, Hashable, Sendable {
    case artifact(ArtifactDefinition)
    case tablet(TabletDefinition)

    var id: String {
        switch self {
        case .artifact(let artifact): "artifact:\(artifact.value)"
        case .tablet(let tablet): "tablet:\(tablet.id)"
        }
    }

    var kind: ItemKind {
        switch self {
        case .artifact: .artifact
        case .tablet: .tablet
        }
    }

    var name: String {
        switch self {
        case .artifact(let artifact): artifact.labelKorean
        case .tablet(let tablet): tablet.koreanName
        }
    }

    var imageURL: URL {
        switch self {
        case .artifact(let artifact): artifact.imageURL
        case .tablet(let tablet): tablet.imageURL
        }
    }
}

enum CatalogError: LocalizedError {
    case bundledCatalogMissing
    case invalidWikiPayload

    var errorDescription: String? {
        switch self {
        case .bundledCatalogMissing: "번들에 아티팩트 목록이 없습니다. scripts/sync_catalog.py를 실행해 주세요."
        case .invalidWikiPayload: "세피리아 위키의 아티팩트 데이터 형식을 해석하지 못했습니다."
        }
    }
}
