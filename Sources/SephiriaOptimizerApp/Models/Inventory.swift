import Foundation

struct GridPosition: Codable, Hashable, Identifiable, Comparable, Sendable {
    let row: Int
    let column: Int

    var id: String { "\(row)-\(column)" }

    static func < (lhs: GridPosition, rhs: GridPosition) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }
}

struct InventoryGrid: Hashable, Sendable {
    static let columnCount = 6
    static let minimumSlotCount = 18
    static let maximumSlotCount = 60

    let slotCount: Int

    init(slotCount: Int) {
        self.slotCount = min(max(slotCount, Self.minimumSlotCount), Self.maximumSlotCount)
    }

    var rowCount: Int { Int(ceil(Double(slotCount) / Double(Self.columnCount))) }

    var positions: [GridPosition] {
        (0..<slotCount).map { GridPosition(row: $0 / Self.columnCount, column: $0 % Self.columnCount) }
    }

    func contains(_ position: GridPosition) -> Bool {
        position.row >= 0 && position.column >= 0 && position.column < Self.columnCount
            && (position.row * Self.columnCount + position.column) < slotCount
    }
}

struct InventoryPiece: Identifiable, Hashable, Sendable {
    let id: UUID
    let item: CatalogItem
    var rotation: Int
    var recognitionConfidence: Float

    init(id: UUID = UUID(), item: CatalogItem, rotation: Int = 0, recognitionConfidence: Float = 1) {
        self.id = id
        self.item = item
        self.rotation = ((rotation % 4) + 4) % 4
        self.recognitionConfidence = recognitionConfidence
    }
}

struct InventoryLayout: Hashable, Sendable {
    let grid: InventoryGrid
    var pieces: [GridPosition: InventoryPiece]

    init(grid: InventoryGrid, pieces: [GridPosition: InventoryPiece] = [:]) {
        self.grid = grid
        self.pieces = pieces.filter { grid.contains($0.key) }
    }
}

struct ArtifactResult: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let position: GridPosition
    let amplification: Int
    let capacity: Int
    let ignoresCondition: Bool

    var overflow: Int { max(0, amplification - capacity) }
}

struct LayoutEvaluation: Hashable, Sendable {
    let artifacts: [ArtifactResult]
    let totalUsefulAmplification: Int
    let fullArtifactCount: Int
    let positiveArtifactCount: Int
    let overflowAmount: Int
    let negativeAmount: Int
    let ignoredConditionCount: Int
    let score: Int

    var hasNoOverflow: Bool { overflowAmount == 0 }
}

struct OptimizationResult: Sendable {
    let original: InventoryLayout
    let optimized: InventoryLayout
    let before: LayoutEvaluation
    let after: LayoutEvaluation
    let iterations: Int
}
